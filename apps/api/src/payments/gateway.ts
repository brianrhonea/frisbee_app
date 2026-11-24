// What the payments routes need from Stripe. stripe.ts is the real one
// (the stripe SDK, from STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET);
// tests pass a fake. Keys, signatures and account links are credentials:
// never log them.

/** A connected account's state, as Stripe reports it. */
export interface GatewayAccount {
  chargesEnabled: boolean;
  detailsSubmitted: boolean;
}

/** One line on the Checkout page. */
export interface CheckoutItem {
  /** e.g. "Bid fee: Spring Fling (Haze)", "Processing fee". */
  name: string;
  amountCents: number;
}

export interface CheckoutInput {
  /** The host's connected account: the charge is made on it (a direct charge). */
  account: string;
  /** The whole charge: the sum of [items]. */
  amountCents: number;
  currency: string;
  /** Stall 10's application fee, less than [amountCents]. */
  feeCents: number;
  /** What the payer sees: the fee, and a processing fee when the host passes the fees on. */
  items: CheckoutItem[];
  successUrl: string;
  cancelUrl: string;
  /** Prefills Checkout's email. */
  email?: string;
  /** Unix seconds: when the Checkout link stops working. */
  expiresAt: number;
  metadata: Record<string, string>;
  /** Stripe's idempotency key, so a retried request makes one session. */
  idempotencyKey: string;
  /**
   * Shown inside the website's page (ui_mode embedded_page) instead of on
   * Stripe's: [successUrl] is where it returns to, [cancelUrl] unused.
   */
  embedded?: boolean;
}

/** A PaymentIntent for the app's own payment sheet (PaymentSheet), as a direct charge. */
export interface IntentInput {
  account: string;
  amountCents: number;
  currency: string;
  feeCents: number;
  /** On the payer's receipt and the host's Dashboard, e.g. "Bid fee: Spring Fling (Haze)". */
  description: string;
  email?: string;
  metadata: Record<string, string>;
  idempotencyKey: string;
}

/**
 * A PaymentIntent as Stripe reports it now: still to pay ("open": no
 * payment yet, or a card declined and the sheet can try again), a bank
 * payment clearing, paid, or cancelled.
 */
export type GatewayIntentStatus = "open" | "processing" | "succeeded" | "canceled";

/** A Checkout session as Stripe reports it now (asked when the payer comes back, besides the webhook). */
export interface GatewayCheckout {
  status: "open" | "complete" | "expired";
  /** "unpaid" on a complete session: a bank payment still clearing. */
  paymentStatus: "paid" | "unpaid" | "no_payment_required";
  paymentIntent: string | null;
  /** The payment itself failed (a bank debit bounced): the session stays complete and unpaid. */
  paymentFailed: boolean;
}

/** A webhook event, reduced to what the routes read. */
export interface GatewayEvent {
  id: string;
  type: string;
  /** The connected account it happened on (Connect events). */
  account: string | null;
  /** event.data.object. */
  object: Record<string, unknown>;
}

export interface PaymentGateway {
  /** A connected account for a host: it pays Stripe's fees, Stripe covers losses, full Stripe Dashboard. */
  createAccount(input: { email?: string; name: string; idempotencyKey: string }): Promise<string>;
  /** A single-use onboarding link for [account]. */
  onboardingLink(account: string, refreshUrl: string, returnUrl: string): Promise<string>;
  /** An AccountSession's client secret for the embedded onboarding and account management of [account]. */
  accountSession(account: string): Promise<string>;
  account(account: string): Promise<GatewayAccount>;
  /** A Checkout session: [url] for a hosted one, [clientSecret] for an embedded one. */
  createCheckout(input: CheckoutInput): Promise<{ id: string; url: string | null; clientSecret: string | null }>;
  /** A PaymentIntent on [IntentInput.account], with its client secret for the payment sheet. */
  createIntent(input: IntentInput): Promise<{ id: string; clientSecret: string }>;
  /** The PaymentIntent [id] on [account], as it stands now. */
  intent(account: string, id: string): Promise<{ status: GatewayIntentStatus; clientSecret: string }>;
  /** Cancels a PaymentIntent nobody paid; throws if it can't be (paid, or clearing). */
  cancelIntent(account: string, id: string): Promise<void>;
  /** The session [id] on [account], as it stands now. */
  checkout(account: string, id: string): Promise<GatewayCheckout>;
  /** Stops an open session taking payment; throws if it isn't open any more. */
  expireCheckout(account: string, id: string): Promise<void>;
  /** Refunds a payment in full, Stall 10's fee included (a duplicate payment). */
  refund(account: string, paymentIntent: string, idempotencyKey: string): Promise<void>;
  /** Gives Stall 10's fee back after the host refunded the charge in Stripe. */
  refundApplicationFee(feeId: string, idempotencyKey: string): Promise<void>;
  /** The event in [rawBody], or throws when the signature doesn't match. */
  verifyEvent(rawBody: Buffer, signature: string): GatewayEvent;
}
