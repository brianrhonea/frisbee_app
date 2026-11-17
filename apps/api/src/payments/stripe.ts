// The real PaymentGateway: the stripe SDK with STRIPE_SECRET_KEY (the
// platform's secret key, sk_test_… on dev) and STRIPE_WEBHOOK_SECRET (the
// signing secret of the Connect webhook endpoint, whsec_…). Never commit
// them; on Cloud Run they come from Secret Manager (apps/api/DEPLOY.md,
// "Payments"). Without both, online payments are off.
import Stripe from "stripe";
import type { GatewayEvent, PaymentGateway } from "./gateway.js";

const id = (v: unknown): string => (typeof v === "string" ? v : ((v as { id?: string } | null)?.id ?? ""));

export function stripeFromEnv(env: NodeJS.ProcessEnv = process.env): PaymentGateway | undefined {
  const key = env.STRIPE_SECRET_KEY?.trim();
  const webhookSecret = env.STRIPE_WEBHOOK_SECRET?.trim();
  if (!key || !webhookSecret) return undefined;
  const stripe = new Stripe(key, { maxNetworkRetries: 2, timeout: 20_000 });
  return {
    async createAccount({ email, name, idempotencyKey }) {
      const account = await stripe.accounts.create(
        {
          country: "US",
          ...(email && { email }),
          business_profile: { name },
          // A Standard-style account: the host pays Stripe's fees, Stripe
          // covers negative balances, and the host has the full Dashboard
          // (refunds, disputes, payouts happen there).
          controller: {
            fees: { payer: "account" },
            losses: { payments: "stripe" },
            stripe_dashboard: { type: "full" },
          },
          capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
        },
        { idempotencyKey },
      );
      return account.id;
    },
    async onboardingLink(account, refreshUrl, returnUrl) {
      const link = await stripe.accountLinks.create({ account, refresh_url: refreshUrl, return_url: returnUrl, type: "account_onboarding" });
      return link.url;
    },
    async account(account) {
      const a = await stripe.accounts.retrieve(account);
      return { chargesEnabled: a.charges_enabled === true, detailsSubmitted: a.details_submitted === true };
    },
    async createCheckout(input) {
      const session = await stripe.checkout.sessions.create(
        {
          mode: "payment",
          line_items: [
            {
              quantity: 1,
              price_data: { currency: input.currency.toLowerCase(), unit_amount: input.amountCents, product_data: { name: input.name } },
            },
          ],
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
