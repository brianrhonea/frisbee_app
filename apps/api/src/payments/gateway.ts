// What the payments routes need from Stripe. stripe.ts is the real one
// (the stripe SDK, from STRIPE_SECRET_KEY and the webhook signing
// secrets); tests pass a fake. Keys, signatures, account links and client
// secrets are credentials: never log them.
//
// Since API 0.47.0 Stall 10 is the merchant: every charge is made on
// Stall 10's own account ("platform" charges, `account` null below) and
// the host's share is sent later as a Transfer to the host's payout-only
// connected account (separate charges and transfers). Charges made before
// that were direct charges on the host's account; the methods that act on
// an existing charge still take its account, so those keep working.

/** A host's payout account, as Stripe reports it. */
export interface GatewayAccount {
  /** Stripe can send it transfers (the recipient's stripe_transfers capability is active). */
  transfersEnabled: boolean;
  /** Nothing is waiting on the host (no requirement awaiting them). */
  detailsSubmitted: boolean;
}

/** One line on the Checkout page. */
export interface CheckoutItem {
  /** e.g. "Bid fee: Spring Fling (Haze)", "Service and processing fees". */
  name: string;
  amountCents: number;
}

export interface CheckoutInput {
  /** The whole charge: the sum of [items]. */
  amountCents: number;
  currency: string;
  /** What the payer sees: the fee, and the service and processing fees. */
  items: CheckoutItem[];
  successUrl: string;
  cancelUrl: string;
  /** Prefills Checkout's email. */
  email?: string;
  /** Unix seconds: when the Checkout link stops working. */
  expiresAt: number;
  metadata: Record<string, string>;
  /** Groups the charge with the transfer that later pays the host (the tournament). */
  transferGroup: string;
  /** Stripe's idempotency key, so a retried request makes one session. */
  idempotencyKey: string;
  /**
   * Shown inside the website's page (ui_mode embedded_page) instead of on
   * Stripe's: [successUrl] is where it returns to, [cancelUrl] unused.
   */
  embedded?: boolean;
}

/** A PaymentIntent on Stall 10's account for the app's own payment sheet (PaymentSheet). */
export interface IntentInput {
  amountCents: number;
  currency: string;
  /** On the payer's receipt, e.g. "Bid fee: Spring Fling (Haze)". */
  description: string;
  email?: string;
  metadata: Record<string, string>;
  transferGroup: string;
  idempotencyKey: string;
}

/**
 * Stripe couldn't take money back from a host's account: its balance is
 * short (already paid out to the bank). Every other failure is thrown as
 * itself, so callers retry it with the same idempotency key.
 */
export class InsufficientBalance extends Error {
  constructor() {
    super("The host's balance is too low to take it back.");
    this.name = "InsufficientBalance";
  }
}

/** A host's share, sent to its payout account once the event is over. */
export interface TransferInput {
  /** The host's connected account. */
  destination: string;
  amountCents: number;
  currency: string;
  /**
   * The Stripe charge (ch_…) the money came from: the transfer waits for
   * its funds. None: from Stall 10's balance (giving a host back what was
   * taken from them by mistake).
   */
  sourceTransaction?: string;
  transferGroup: string;
  metadata: Record<string, string>;
  idempotencyKey: string;
}

/**
 * A PaymentIntent as Stripe reports it now: still to pay ("open": no
 * payment yet, or a card declined and the sheet can try again), a bank
 * payment clearing, paid, or cancelled.
 */
export type GatewayIntentStatus = "open" | "processing" | "succeeded" | "canceled";

/** What Stripe says about one payment on Stall 10's account, for the daily check. */
export interface GatewayPaymentSummary {
  status: GatewayIntentStatus;
  amountCents: number;
  refundedCents: number;
  /** The latest dispute's state: none, open (being decided), won or lost. */
  dispute: "none" | "open" | "won" | "lost";
}

/** What Stripe says about one transfer to a host. */
export interface GatewayTransferSummary {
  destination: string;
  amountCents: number;
  reversedCents: number;
}

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
  /** The connected account it happened on (Connect events); null for Stall 10's own account. */
  account: string | null;
  /** event.data.object. */
  object: Record<string, unknown>;
}

export interface PaymentGateway {
  /**
   * A payout-only account for a host (Accounts v2 recipient, no Stripe
   * Dashboard or login: everything is shown inside Stall 10). Stall 10
   * pays its fees and covers its negative balance.
   */
  createAccount(input: { email?: string; name: string; idempotencyKey: string }): Promise<string>;
  /** A single-use onboarding link for [account] (the fallback when the embedded form can't load). */
  onboardingLink(account: string, refreshUrl: string, returnUrl: string): Promise<string>;
  /** An AccountSession's client secret: onboarding, bank details and payouts shown inside Stall 10. */
  accountSession(account: string): Promise<string>;
  account(account: string): Promise<GatewayAccount>;
  /** A Checkout session on Stall 10's account: [url] for a hosted one, [clientSecret] for an embedded one. */
  createCheckout(input: CheckoutInput): Promise<{ id: string; url: string | null; clientSecret: string | null }>;
  /** A PaymentIntent on Stall 10's account, with its client secret for the payment sheet. */
  createIntent(input: IntentInput): Promise<{ id: string; clientSecret: string }>;
  /** The PaymentIntent [id] (on [account], or Stall 10's when null), as it stands now. */
  intent(account: string | null, id: string): Promise<{ status: GatewayIntentStatus; clientSecret: string }>;
  /** Cancels a PaymentIntent nobody paid; throws if it can't be (paid, or clearing). */
  cancelIntent(account: string | null, id: string): Promise<void>;
  /** The session [id], as it stands now. */
  checkout(account: string | null, id: string): Promise<GatewayCheckout>;
  /** Stops an open session taking payment; throws if it isn't open any more. */
  expireCheckout(account: string | null, id: string): Promise<void>;
  /** The charge (ch_…) a paid PaymentIntent on Stall 10's account made. */
  chargeOf(paymentIntent: string): Promise<string>;
  /** Refunds [amountCents] of a payment (all of it when undefined), Stall 10's fee included on a direct charge. */
  refund(account: string | null, paymentIntent: string, amountCents: number | undefined, idempotencyKey: string): Promise<void>;
  /** Gives Stall 10's fee back after the host refunded a direct charge in Stripe. */
  refundApplicationFee(feeId: string, idempotencyKey: string): Promise<void>;
  /** Sends a host its share; the transfer's id. */
  transfer(input: TransferInput): Promise<string>;
  /**
   * A transfer already made for release [n] of [chargeId] in [transferGroup]
   * (its metadata), or null: checked before retrying an old release, as
   * Stripe forgets idempotency keys after 24 hours.
   */
  findTransfer(transferGroup: string, chargeId: string, n: number): Promise<string | null>;
  /** Takes [amountCents] of a transfer back from the host (a refund or a dispute); InsufficientBalance when it isn't there. */
  reverseTransfer(transferId: string, amountCents: number, idempotencyKey: string): Promise<void>;
  /** A payment's state on Stripe (Stall 10's account), for the daily check. */
  paymentSummary(paymentIntent: string): Promise<GatewayPaymentSummary>;
  /** A transfer's state on Stripe, for the daily check. */
  transferSummary(transferId: string): Promise<GatewayTransferSummary>;
  /** The event in [rawBody], or throws when the signature matches none of the endpoints' secrets. */
  verifyEvent(rawBody: Buffer, signature: string): GatewayEvent;
}
