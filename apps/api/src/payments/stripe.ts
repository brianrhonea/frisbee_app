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
      // Embedded: shown in the website's own page; it comes back to
      // [successUrl] with the session's id when a payment needs a redirect.
      const where = input.embedded
        ? { ui_mode: "embedded_page" as const, return_url: `${input.successUrl}&session_id={CHECKOUT_SESSION_ID}` }
        : { success_url: input.successUrl, cancel_url: input.cancelUrl };
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
          ...where,
          expires_at: input.expiresAt,
        },
        { stripeAccount: input.account, idempotencyKey: input.idempotencyKey },
      );
      if (input.embedded) {
        if (!session.client_secret) throw new Error("Stripe returned no Checkout client secret.");
        return { id: session.id, url: null, clientSecret: session.client_secret };
      }
      if (!session.url) throw new Error("Stripe returned no Checkout URL.");
      return { id: session.id, url: session.url, clientSecret: null };
    },
    async createIntent(input) {
      // A direct charge on the host's account, as Checkout's are: the
      // payment methods the host has on (cards, wallets, bank payments)
      // come from its settings, never a list here.
      const pi = await stripe.paymentIntents.create(
        {
          amount: input.amountCents,
          currency: input.currency.toLowerCase(),
          automatic_payment_methods: { enabled: true },
          application_fee_amount: input.feeCents,
          description: input.description,
          metadata: input.metadata,
          ...(input.email && { receipt_email: input.email }),
        },
        { stripeAccount: input.account, idempotencyKey: input.idempotencyKey },
      );
      if (!pi.client_secret) throw new Error("Stripe returned no PaymentIntent client secret.");
      return { id: pi.id, clientSecret: pi.client_secret };
    },
    async intent(account, intentId) {
      // Asked while the payer waits, as checkout() is.
      const pi = await stripe.paymentIntents.retrieve(intentId, {}, { stripeAccount: account, timeout: 5_000, maxNetworkRetries: 0 });
      const status = pi.status === "succeeded" ? "succeeded" : pi.status === "processing" ? "processing" : pi.status === "canceled" ? "canceled" : "open";
      return { status, clientSecret: pi.client_secret ?? "" };
    },
    async cancelIntent(account, intentId) {
      await stripe.paymentIntents.cancel(intentId, {}, { stripeAccount: account });
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
