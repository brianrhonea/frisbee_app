// The real PaymentGateway: the stripe SDK with STRIPE_SECRET_KEY (the
// platform's secret key, sk_test_… on dev; a restricted rk_… key in
// production) and the webhook signing secrets (whsec_…):
// STRIPE_PLATFORM_WEBHOOK_SECRET for the endpoint that receives Stall 10's
// own account's events (charges, refunds, disputes, transfers) and
// STRIPE_WEBHOOK_SECRET for the Connect endpoint (hosts' payout accounts).
// Never commit them; on Cloud Run they come from Secret Manager
// (apps/api/DEPLOY.md, "Payments"). Without the key and one secret,
// online payments are off.
import Stripe from "stripe";
import { type GatewayCheckout, type GatewayEvent, InsufficientBalance, type PaymentGateway } from "./gateway.js";

const id = (v: unknown): string => (typeof v === "string" ? v : ((v as { id?: string } | null)?.id ?? ""));

/** A direct charge's account (made before 0.47.0), or Stall 10's own (no header). */
const on = (account: string | null) => (account ? { stripeAccount: account } : {});

/** Everything is shown inside Stall 10, so nobody is asked to sign in to Stripe. */
const inApp = { external_account_collection: true, disable_stripe_user_authentication: true };

export function stripeFromEnv(env: NodeJS.ProcessEnv = process.env): PaymentGateway | undefined {
  const key = env.STRIPE_SECRET_KEY?.trim();
  const secrets = [env.STRIPE_PLATFORM_WEBHOOK_SECRET, env.STRIPE_WEBHOOK_SECRET].map((s) => s?.trim() ?? "").filter((s) => s !== "");
  if (!key || secrets.length === 0) return undefined;
  const stripe = new Stripe(key, { maxNetworkRetries: 2, timeout: 20_000 });
  return {
    async createAccount({ email, name, idempotencyKey }) {
      // Accounts v2 (POST /v2/core/accounts): a recipient that only
      // receives transfers, with no Stripe Dashboard (dashboard "none"):
      // the host never signs in to Stripe. Stall 10 pays its fees and
      // covers its negative balance (a refund or dispute after payout).
      const account = await stripe.v2.core.accounts.create(
        {
          ...(email && { contact_email: email }),
          display_name: name,
          dashboard: "none",
          identity: { country: "us" },
          defaults: { currency: "usd", responsibilities: { fees_collector: "application", losses_collector: "application" } },
          configuration: { recipient: { capabilities: { stripe_balance: { stripe_transfers: { requested: true } } } } },
        },
        { idempotencyKey },
      );
      return account.id;
    },
    async onboardingLink(account, refreshUrl, returnUrl) {
      const link = await stripe.v2.core.accountLinks.create({
        account,
        use_case: {
          type: "account_onboarding",
          account_onboarding: { refresh_url: refreshUrl, return_url: returnUrl },
        },
      });
      return link.url;
    },
    async accountSession(account) {
      // Connect embedded components inside the app and website: setup,
      // what Stripe still needs, the bank account, and payouts.
      const session = await stripe.accountSessions.create({
        account,
        components: {
          account_onboarding: { enabled: true, features: inApp },
          account_management: { enabled: true, features: inApp },
          notification_banner: { enabled: true, features: inApp },
          payouts: { enabled: true, features: { ...inApp, instant_payouts: false, standard_payouts: true, edit_payout_schedule: false } },
        },
      });
      return session.client_secret;
    },
    async account(account) {
      const a = await stripe.v2.core.accounts.retrieve(account, { include: ["configuration.recipient", "requirements"] });
      const transfers = a.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status;
      const owed = (a.requirements?.entries ?? []).some((e) => e.awaiting_action_from === "user");
      return { transfersEnabled: transfers === "active", detailsSubmitted: !owed };
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
          payment_intent_data: { transfer_group: input.transferGroup, metadata: input.metadata },
          metadata: input.metadata,
          ...(input.email && { customer_email: input.email }),
          ...where,
          expires_at: input.expiresAt,
        },
        { idempotencyKey: input.idempotencyKey },
      );
      if (input.embedded) {
        if (!session.client_secret) throw new Error("Stripe returned no Checkout client secret.");
        return { id: session.id, url: null, clientSecret: session.client_secret };
      }
      if (!session.url) throw new Error("Stripe returned no Checkout URL.");
      return { id: session.id, url: session.url, clientSecret: null };
    },
    async createIntent(input) {
      // The payment methods on (cards, wallets, bank payments) come from
      // Stall 10's settings, never a list here.
      const pi = await stripe.paymentIntents.create(
        {
          amount: input.amountCents,
          currency: input.currency.toLowerCase(),
          automatic_payment_methods: { enabled: true },
          transfer_group: input.transferGroup,
          description: input.description,
          metadata: input.metadata,
          ...(input.email && { receipt_email: input.email }),
        },
        { idempotencyKey: input.idempotencyKey },
      );
      if (!pi.client_secret) throw new Error("Stripe returned no PaymentIntent client secret.");
      return { id: pi.id, clientSecret: pi.client_secret };
    },
    async intent(account, intentId) {
      // Asked while the payer waits, as checkout() is.
      const pi = await stripe.paymentIntents.retrieve(intentId, {}, { ...on(account), timeout: 5_000, maxNetworkRetries: 0 });
      const status = pi.status === "succeeded" ? "succeeded" : pi.status === "processing" ? "processing" : pi.status === "canceled" ? "canceled" : "open";
      return { status, clientSecret: pi.client_secret ?? "" };
    },
    async cancelIntent(account, intentId) {
      await stripe.paymentIntents.cancel(intentId, {}, on(account));
    },
    async checkout(account, sessionId) {
      // Asked while the payer waits: short, no retries; the caller falls
      // back to what's stored and the webhook catches up.
      const s = await stripe.checkout.sessions.retrieve(sessionId, { expand: ["payment_intent"] }, { ...on(account), timeout: 5_000, maxNetworkRetries: 0 });
      const pi = typeof s.payment_intent === "object" && s.payment_intent ? s.payment_intent : null;
      const status: GatewayCheckout["status"] = s.status === "complete" ? "complete" : s.status === "expired" ? "expired" : "open";
      const paymentStatus: GatewayCheckout["paymentStatus"] = s.payment_status === "paid" ? "paid" : s.payment_status === "no_payment_required" ? "no_payment_required" : "unpaid";
      const paymentFailed = pi !== null && (pi.status === "requires_payment_method" || pi.status === "canceled") && s.status === "complete";
      return { status, paymentStatus, paymentIntent: id(s.payment_intent) || null, paymentFailed };
    },
    async expireCheckout(account, sessionId) {
      await stripe.checkout.sessions.expire(sessionId, {}, on(account));
    },
    async chargeOf(paymentIntent) {
      const pi = await stripe.paymentIntents.retrieve(paymentIntent);
      const charge = id(pi.latest_charge);
      if (!charge) throw new Error("That payment has no charge yet.");
      return charge;
    },
    async refund(account, paymentIntent, amountCents, idempotencyKey) {
      await stripe.refunds.create(
        {
          payment_intent: paymentIntent,
          ...(amountCents !== undefined && { amount: amountCents }),
          // Only a direct charge carries Stall 10's application fee.
          ...(account && { refund_application_fee: true }),
        },
        { ...on(account), idempotencyKey },
      );
    },
    async refundApplicationFee(feeId, idempotencyKey) {
      await stripe.applicationFees.createRefund(feeId, {}, { idempotencyKey });
    },
    async transfer(input) {
      const t = await stripe.transfers.create(
        {
          amount: input.amountCents,
          currency: input.currency.toLowerCase(),
          destination: input.destination,
          ...(input.sourceTransaction && { source_transaction: input.sourceTransaction }),
          transfer_group: input.transferGroup,
          metadata: input.metadata,
        },
        { idempotencyKey: input.idempotencyKey },
      );
      return t.id;
    },
    async reverseTransfer(transferId, amountCents, idempotencyKey) {
      try {
        await stripe.transfers.createReversal(transferId, { amount: amountCents }, { idempotencyKey });
      } catch (e) {
        const code = (e as { code?: string }).code;
        if (code === "balance_insufficient" || code === "insufficient_funds") throw new InsufficientBalance();
        throw e;
      }
    },
    async paymentSummary(paymentIntent) {
      const pi = await stripe.paymentIntents.retrieve(paymentIntent, { expand: ["latest_charge"] });
      const charge = typeof pi.latest_charge === "object" ? pi.latest_charge : null;
      const status = pi.status === "succeeded" ? "succeeded" : pi.status === "processing" ? "processing" : pi.status === "canceled" ? "canceled" : "open";
      let dispute: "none" | "open" | "won" | "lost" = "none";
      if (charge?.disputed) {
        const latest = (await stripe.disputes.list({ payment_intent: paymentIntent, limit: 1 })).data[0];
        dispute = !latest ? "open" : latest.status === "won" ? "won" : latest.status === "lost" ? "lost" : "open";
      }
      return { status, amountCents: pi.amount_received || pi.amount, refundedCents: charge?.amount_refunded ?? 0, dispute };
    },
    async transferSummary(transferId) {
      const t = await stripe.transfers.retrieve(transferId);
      return { destination: id(t.destination), amountCents: t.amount, reversedCents: t.amount_reversed };
    },
    verifyEvent(rawBody, signature): GatewayEvent {
      let event: Stripe.Event | undefined;
      for (const secret of secrets) {
        try {
          event = stripe.webhooks.constructEvent(rawBody, signature, secret);
          break;
        } catch {
          // Signed for the other endpoint, or not by Stripe: try the next.
        }
      }
      if (!event) throw new Error("Bad signature.");
      const e = event as unknown as { id: string; type: string; account?: string; data: { object: Record<string, unknown> } };
      return { id: e.id, type: e.type, account: e.account ?? null, object: { ...e.data.object, id: id(e.data.object.id) } };
    },
  };
}
