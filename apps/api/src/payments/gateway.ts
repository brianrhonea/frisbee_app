// What the payments routes need from Stripe. stripe.ts is the real one
// (the stripe SDK, from STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET);
// tests pass a fake. Keys, signatures and account links are credentials:
// never log them.

/** A connected account's state, as Stripe reports it. */
export interface GatewayAccount {
  chargesEnabled: boolean;
  detailsSubmitted: boolean;
}

export interface CheckoutInput {
  /** The host's connected account: the charge is made on it (a direct charge). */
  account: string;
  amountCents: number;
  currency: string;
  /** Stall 10's application fee, less than [amountCents]. */
  feeCents: number;
  /** The line the payer sees, e.g. "Bid fee: Spring Fling (Haze)". */
  name: string;
  successUrl: string;
  cancelUrl: string;
  /** Prefills Checkout's email. */
  email?: string;
  /** Unix seconds: when the Checkout link stops working. */
  expiresAt: number;
  metadata: Record<string, string>;
  /** Stripe's idempotency key, so a retried request makes one session. */
  idempotencyKey: string;
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
  account(account: string): Promise<GatewayAccount>;
  createCheckout(input: CheckoutInput): Promise<{ id: string; url: string }>;
  /** Refunds a payment in full, Stall 10's fee included (a duplicate payment). */
  refund(account: string, paymentIntent: string, idempotencyKey: string): Promise<void>;
  /** Gives Stall 10's fee back after the host refunded the charge in Stripe. */
  refundApplicationFee(feeId: string, idempotencyKey: string): Promise<void>;
  /** The event in [rawBody], or throws when the signature doesn't match. */
  verifyEvent(rawBody: Buffer, signature: string): GatewayEvent;
}
