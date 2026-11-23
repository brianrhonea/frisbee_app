// The real PaymentGateway (Accounts v2 for hosts): the stripe SDK with STRIPE_SECRET_KEY (the
// platform's secret key, sk_test_… on dev) and STRIPE_WEBHOOK_SECRET (the
// signing secret of the Connect webhook endpoint, whsec_…). Never commit
// them; on Cloud Run they come from Secret Manager (apps/api/DEPLOY.md,
// "Payments"). Without both, online payments are off.
import Stripe from "stripe";
import type { GatewayCheckout, GatewayEvent, PaymentGateway } from "./gateway.js";

const id = (v: unknown): string => (typeof v === "string" ? v : ((v as { id?: string } | null)?.id ?? ""));

export function stripeFromEnv(env: NodeJS.ProcessEnv = process.env): PaymentGateway | undefined {
  const key = env.STRIPE_SECRET_KEY?.trim();
  const webhookSecret = env.STRIPE_WEBHOOK_SECRET?.trim();
  if (!key || !webhookSecret) return undefined;
  const stripe = new Stripe(key, { maxNetworkRetries: 2, timeout: 20_000 });
  return {
    async createAccount({ email, name, idempotencyKey }) {
      // Accounts v2 (POST /v2/core/accounts), a merchant the charges are
      // made on (direct charges): the host pays Stripe's fees, Stripe
      // covers negative balances, and the host has the full Dashboard
      // (refunds, disputes and payouts happen there). Bank payments (ACH
      // Direct Debit) show in Checkout once that capability is active.
      const account = await stripe.v2.core.accounts.create(
        {
          ...(email && { contact_email: email }),
          display_name: name,
          dashboard: "full",
          identity: { country: "us" },
          defaults: { currency: "usd", responsibilities: { fees_collector: "stripe", losses_collector: "stripe" } },
          configuration: {
            merchant: { capabilities: { card_payments: { requested: true }, ach_debit_payments: { requested: true } } },
          },
        },
        { idempotencyKey },
      );
      return account.id;
    },
    async onboardingLink(account, refreshUrl, returnUrl) {
      const link = await stripe.v2.core.accountLinks.create({
        account,
        use_case: { type: "account_onboarding", account_onboarding: { refresh_url: refreshUrl, return_url: returnUrl } },
      });
      return link.url;
    },
    async account(account) {
      // v2's capability status, not v1's charges_enabled.
      const a = await stripe.v2.core.accounts.retrieve(account, { include: ["configuration.merchant", "requirements"] });
      const cards = a.configuration?.merchant?.capabilities?.card_payments?.status;
      const owed = (a.requirements?.entries ?? []).some((e) => e.awaiting_action_from === "user");
      return { chargesEnabled: cards === "active", detailsSubmitted: !owed };
    },
    async createCheckout(input) {
      const session = await stripe.checkout.sessions.create(
        {
          mode: "payment",
          line_items: input.items.map((item) => ({
            quantity: 1,
            price_data: { currency: input.currency.toLowerCase(), unit_amount: item.amountCents, product_data: { name: item.name } },
          })),
          payment_intent_data: { application_fee_amount: input.feeCents, metadata: input.metadata },
          metadata: input.metadata,
          ...(input.email && { customer_email: input.email }),
          success_url: input.successUrl,
          cancel_url: input.cancelUrl,
          expires_at: input.expiresAt,
        },
        { stripeAccount: input.account, idempotencyKey: input.idempotencyKey },
      );
      if (!session.url) throw new Error("Stripe returned no Checkout URL.");
      return { id: session.id, url: session.url };
    },
    async checkout(account, sessionId) {
      // Asked while the payer waits: short, no retries; the caller falls
      // back to what's stored and the webhook catches up.
      const s = await stripe.checkout.sessions.retrieve(sessionId, { expand: ["payment_intent"] }, { stripeAccount: account, timeout: 5_000, maxNetworkRetries: 0 });
      const pi = typeof s.payment_intent === "object" && s.payment_intent ? s.payment_intent : null;
      const status: GatewayCheckout["status"] = s.status === "complete" ? "complete" : s.status === "expired" ? "expired" : "open";
      const paymentStatus: GatewayCheckout["paymentStatus"] = s.payment_status === "paid" ? "paid" : s.payment_status === "no_payment_required" ? "no_payment_required" : "unpaid";
      const paymentFailed = pi !== null && (pi.status === "requires_payment_method" || pi.status === "canceled") && s.status === "complete";
      return { status, paymentStatus, paymentIntent: id(s.payment_intent) || null, paymentFailed };
    },
    async expireCheckout(account, sessionId) {
      await stripe.checkout.sessions.expire(sessionId, {}, { stripeAccount: account });
    },
    async refund(account, paymentIntent, idempotencyKey) {
      await stripe.refunds.create({ payment_intent: paymentIntent, refund_application_fee: true }, { stripeAccount: account, idempotencyKey });
    },
    async refundApplicationFee(feeId, idempotencyKey) {
      await stripe.applicationFees.createRefund(feeId, {}, { idempotencyKey });
    },
    verifyEvent(rawBody, signature): GatewayEvent {
      const event = stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
      const e = event as unknown as { id: string; type: string; account?: string; data: { object: Record<string, unknown> } };
      return { id: e.id, type: e.type, account: e.account ?? null, object: { ...e.data.object, id: id(e.data.object.id) } };
    },
  };
}
