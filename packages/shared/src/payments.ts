// Online payments for tournament and league fees (Stripe Connect).
//
// Stall 10 takes every payment (it's the merchant on the payer's
// statement) and holds it until the event is over, then sends the host the
// fee it set: the payer pays that plus Stall 10's service fee and Stripe's
// processing fee (PlatformFee, stripeCardFeeEstimate). A host links a
// payout account inside Stall 10 once (no Stripe login); teams pay their
// bid or spot fee, and players their entry fee, in the app's payment sheet
// or Checkout. Paying marks the same `tournaments/{id}/payments/{payerId}`
// record the host can still set by hand, so instructions-and-mark-paid
// keeps working beside it.
import { z } from "zod";

/** Stall 10's cut of each payment: a percentage (basis points) plus a fixed amount. */
export interface PlatformFee {
  /** 100 = 1%. */
  percentBps: number;
  fixedCents: number;
}

/**
 * 3% of the fee (docs/product-spec.md §7), added to what the payer pays,
 * never taken from the host. The API reads PLATFORM_FEE_BPS /
 * PLATFORM_FEE_FIXED_CENTS.
 */
export const defaultPlatformFee: PlatformFee = { percentBps: 300, fixedCents: 0 };

export const paymentLimits = {
  /** Stripe's smallest USD charge. */
  minChargeCents: 50,
  /** Checkout links last an hour; after that the payer starts again. */
  checkoutMinutes: 60,
} as const;

/** Stall 10's fee on [amountCents], rounded to the cent. */
export function platformFeeCents(amountCents: number, fee: PlatformFee): number {
  return Math.round((amountCents * fee.percentBps) / 10_000) + fee.fixedCents;
}

/**
 * Why [amountCents] can't be paid online, or null. Stripe needs at least
 * 50¢, and its application fee must be less than the charge.
 */
export function onlinePaymentProblem(amountCents: number, currency: string, fee: PlatformFee): string | null {
  if (currency !== "USD") return "Online payments are in US dollars only.";
  if (amountCents < paymentLimits.minChargeCents) return "This fee is too small to pay online.";
  if (platformFeeCents(amountCents, fee) >= amountCents) return "This fee is too small to pay online.";
  return null;
}

/** "1% + $1", "2.5%", "$1": the fee as hosts and payers read it. */
export function platformFeeLabel(fee: PlatformFee): string {
  const pct = fee.percentBps > 0 ? `${trimZeros((fee.percentBps / 100).toFixed(2))}%` : "";
  const fixed = fee.fixedCents > 0 ? centsLabel(fee.fixedCents) : "";
  return [pct, fixed].filter(Boolean).join(" + ") || "nothing";
}

/**
 * Stripe's standard US online card rate (2.9% + 30¢), which the host pays
 * on each payment. An estimate for showing hosts what they'll get:
 * international cards, other payment methods or a host's own Stripe
 * pricing cost more or less.
 */
export const stripeCardFeeEstimate: PlatformFee = { percentBps: 290, fixedCents: 30 };

/** Where a fee paid online goes. */
export interface FeeBreakdown {
  /** What the payer is charged: the fee itself, nothing added. */
  amountCents: number;
  /** Stall 10's fee. */
  platformCents: number;
  /** Stripe's card fee (an estimate). */
  stripeCents: number;
  /** What reaches the host's Stripe balance, about. */
  hostCents: number;
}

/** How [amountCents] paid online splits between Stall 10, Stripe and the host. */
export function feeBreakdown(amountCents: number, platform: PlatformFee, card: PlatformFee = stripeCardFeeEstimate): FeeBreakdown {
  const platformCents = platformFeeCents(amountCents, platform);
  const stripeCents = platformFeeCents(amountCents, card);
  return { amountCents, platformCents, stripeCents, hostCents: Math.max(0, amountCents - platformCents - stripeCents) };
}

/** What the payer is charged online for [amountCents]: [onlineCharge]'s charge. */
export function chargeCoveringFees(amountCents: number, platform: PlatformFee, card: PlatformFee = stripeCardFeeEstimate): number {
  return onlineCharge({ amountCents }, platform, card).chargeCents;
}

/**
 * What a payer is charged online for [fee]: the fee, plus Stall 10's fee
 * on it ([platform], e.g. 3%), plus Stripe's card fee on the whole charge,
 * so the full fee reaches the host. Always: hosts never pay the fees.
 * [processingCents] is everything added (Stall 10's and Stripe's);
 * [platformCents] is Stall 10's application fee. A cheaper bank payment
 * leaves the host a little more; it's never a card surcharge.
 */
export function onlineCharge(fee: { amountCents: number }, platform: PlatformFee, card: PlatformFee = stripeCardFeeEstimate): { chargeCents: number; processingCents: number; platformCents: number } {
  const amount = fee.amountCents;
  if (amount <= 0) return { chargeCents: amount, processingCents: 0, platformCents: 0 };
  const platformCents = platformFeeCents(amount, platform);
  const rate = card.percentBps / 10_000;
  let chargeCents = Math.max(amount + platformCents, Math.floor((amount + platformCents + card.fixedCents) / (1 - rate)) - 2);
  while (chargeCents - platformCents - platformFeeCents(chargeCents, card) < amount) chargeCents++;
  return { chargeCents, processingCents: chargeCents - amount, platformCents };
}

/** "$1", "$1.50". */
export function centsLabel(cents: number): string {
  const whole = Math.floor(cents / 100);
  const rest = cents % 100;
  return rest === 0 ? `$${whole}` : `$${whole}.${String(rest).padStart(2, "0")}`;
}

const trimZeros = (s: string) => s.replace(/\.?0+$/, "");

/** Where a host's Stripe account stands. */
export const payoutStatuses = ["none", "pending", "ready"] as const;
export type PayoutStatus = (typeof payoutStatuses)[number];

/**
 * GET /v1/teams/:teamId/payouts: the host's payout account, for anyone who
 * manages its events (only the owner sets it up: [canSetUp]).
 */
export interface PayoutAccountView {
  /** false: online payments aren't set up on this server; hide the section. */
  available: boolean;
  /** none: not connected; pending: Stripe still needs details; ready: can take payments. */
  status: PayoutStatus;
  /** Stall 10's fee, e.g. "3%". */
  feeLabel: string;
  /** The caller is the owner, who sets payments up; others see the status and who to ask. */
  canSetUp: boolean;
  /** The owner's name, for "Ask <owner> to set up payments". */
  ownerName: string;
}

/** What the payments status says, for every place that shows it (team settings, the event form, the event page). */
export const payoutStatusLabels: Record<PayoutStatus, { label: string; summary: string }> = {
  none: { label: "Not set up", summary: "Set up payments to take entry fees online." },
  pending: { label: "Finish setup", summary: "Stripe needs a few more details before you can take payments." },
  ready: { label: "On", summary: "Fees paid online are sent to your bank account a few days after each event." },
};

/**
 * POST /v1/teams/:teamId/payouts/session: Stripe's onboarding shown inside
 * the app or website (Connect embedded components, an AccountSession).
 * [clientSecret] is a credential: never log or store it.
 */
export interface PayoutSessionResult {
  clientSecret: string;
}

/** POST /v1/teams/:teamId/payouts/link: the Stripe page to open (single use, expires in minutes). */
export interface PayoutLinkResult {
  url: string;
}

/** GET /v1/payments/fees: the fees on a payment made online, for hosts setting a price. */
export interface PaymentFees {
  /** false: online payments aren't set up on this server; say nothing about them. */
  available: boolean;
  /** Stall 10's fee. */
  platform: PlatformFee;
  /** Stripe's card fee, an estimate (stripeCardFeeEstimate). */
  card: PlatformFee;
}

/** Who is paying a tournament fee. */
export const payerKinds = ["team", "player"] as const;
export type PayerKind = (typeof payerKinds)[number];

/** GET /v1/tournaments/:id/pay?team=…: whether the caller can pay this fee online. */
export interface PayOptions {
  /** The host takes payments through Stall 10 and this fee can be paid online. */
  online: boolean;
  /** The fee the host set. */
  amountCents: number;
  /** What paying online costs: [amountCents] plus [processingCents]. */
  chargeCents: number;
  /** Stall 10's and Stripe's fees, added for the payer. */
  processingCents: number;
  currency: string;
  /** Stall 10's part of the charge (included, not added). */
  feeCents: number;
  feeLabel: string;
  /** Already paid (online or marked by the host). */
  paid: boolean;
  /** Why it can't be paid online, when [online] is false and it isn't paid. */
  reason: string | null;
  /**
   * "processing": a bank payment is on its way (days); no new checkout
   * until it succeeds or fails. null otherwise.
   */
  pending: "processing" | null;
  /** When the payer said they'll pay another way (a check, a PO); null if they haven't. */
  offlineAt: string | null;
}

/** A host's note on a payment, e.g. "Check #1042". */
export const paymentNoteMax = 200;

/** PUT /v1/tournaments/:id/pay/offline: the payer says they'll pay another way (or takes it back). */
export const payOfflineRequestSchema = z
  .strictObject({
    payer: z.enum(payerKinds),
    teamId: z.string().min(1).max(128).optional(),
    offline: z.boolean(),
  })
  .refine((r) => (r.payer === "team") === (r.teamId !== undefined), { message: "Say which team is paying." });
export type PayOfflineRequest = z.infer<typeof payOfflineRequestSchema>;

/** PUT /v1/tournaments/:id/payments/:payerId: the host marks a team's or player's fee, with a note. */
export const markPaymentRequestSchema = z.strictObject({
  paid: z.boolean(),
  note: z.string().trim().max(paymentNoteMax).default(""),
});
export type MarkPaymentRequest = z.input<typeof markPaymentRequestSchema>;

/** Shown while a bank payment clears. */
export const processingPaymentNote = "Your bank payment is processing. It can take up to 4 business days.";

/** POST /v1/tournaments/:id/checkout */
export const checkoutRequestSchema = z
  .strictObject({
    payer: z.enum(payerKinds),
    /** The team paying its bid or spot fee; only for payer "team". */
    teamId: z.string().min(1).max(128).optional(),
    /**
     * "hosted": Stripe's own Checkout page to go to ([CheckoutResult.url]);
     * "embedded": Checkout shown inside the website's page
     * ([CheckoutResult.clientSecret], on [CheckoutResult.account]).
     */
    ui: z.enum(["hosted", "embedded"]).default("hosted"),
  })
  .refine((r) => (r.payer === "team") === (r.teamId !== undefined), { message: "Say which team is paying." });
export type CheckoutRequest = z.infer<typeof checkoutRequestSchema>;

/** The Stripe Checkout to open: a page to go to, or one to show in the website's page. */
export interface CheckoutResult {
  /** The hosted page; null for an embedded one. */
  url: string | null;
  /** An embedded Checkout's client secret; null for a hosted one. */
  clientSecret: string | null;
  /** Always null since API 0.47.0 (Stall 10's own account); a host's account before that, for Stripe.js. */
  account: string | null;
}

/**
 * POST /v1/tournaments/:id/pay/intent: the app's own payment sheet (Stripe's
 * PaymentSheet) for the same fee, instead of a web page.
 */
export const paymentIntentRequestSchema = z
  .strictObject({
    payer: z.enum(payerKinds),
    teamId: z.string().min(1).max(128).optional(),
  })
  .refine((r) => (r.payer === "team") === (r.teamId !== undefined), { message: "Say which team is paying." });

/** What the app's payment sheet needs: the payment, made on Stall 10's account. */
export interface PaymentIntentResult {
  clientSecret: string;
  /** Always null since API 0.47.0 (the payment is on Stall 10's own account); a host's account before that. */
  account: string | null;
  /** Shown on the sheet: "Stall 10". */
  merchantName: string;
  /** The whole charge, processing fee included. */
  amountCents: number;
  currency: string;
}

/** The note set on the payment record when Stripe confirms it. */
export const paidOnlineNote = "Paid online through Stall 10";
/** The note set when a host refunded a direct charge in Stripe (before API 0.47.0). */
export const refundedOnlineNote = "Refunded through Stripe";
/** The note set when the fee is refunded through Stall 10. */
export const refundedNote = "Refunded through Stall 10";

/** Told to organizers and payers: when hosts get paid, and what a refund returns. */
export const payoutTimingNote = "Fees paid online are held by Stall 10 and sent to the host a few days after the event is over.";
export const refundPolicyNote = "A refund returns the fee. The service and processing fees aren't refunded.";

/** One fee paid online, as the host's earnings list it. */
export interface EarningsItem {
  tournamentId: string;
  /** The receipt line, e.g. "Bid fee: Spring Fling (Haze)". */
  label: string;
  /** What it came to for the host: the fee held, the amount sent, or the amount refunded. */
  amountCents: number;
  /**
   * held: paid, sent a few days after the event; sent: transferred to the
   * host's payout account; kept: a Stall 10 event's; refunded; disputed:
   * the payer's bank is reviewing it.
   */
  status: "held" | "sent" | "kept" | "refunded" | "disputed";
  /** When it was paid, sent or refunded (ISO). */
  at: string | null;
}

/** GET /v1/teams/:teamId/earnings: the host's fees paid online, for its organizers. */
export interface EarningsView {
  currency: string;
  heldCents: number;
  sentCents: number;
  refundedCents: number;
  disputedCents: number;
  /** Taken back after a refund or dispute but not yet recovered: comes off the next payout. */
  owedCents: number;
  /** The latest 50. */
  items: EarningsItem[];
}

/** POST /v1/payments/release (staff): every fee that was due to go out, sent. */
export interface ReleaseResult {
  checked: number;
  sent: number;
}

/**
 * What the daily check against Stripe can find wrong with one payment
 * (paymentIssues/{charge}, server only). Labels for staff.
 */
export const paymentIssueLabels = {
  not_paid_on_stripe: "Marked paid here, but Stripe hasn't taken the payment",
  paid_not_recorded: "Stripe took the payment, but it isn't marked paid here",
  amount_mismatch: "Stripe charged a different amount",
  refund_not_recorded: "Refunded on Stripe, but not here",
  refund_missing: "Refunded here, but not on Stripe",
  dispute_not_recorded: "Disputed on Stripe, but not here",
  dispute_won_not_recorded: "Dispute won on Stripe, but still disputed here",
  transfer_missing: "Sent to the host here, but Stripe has no transfer",
  transfer_mismatch: "The transfer's amount or account differs from what's recorded",
  reversal_missing: "Taken back from the host here, but the transfer isn't reversed",
  release_stuck: "A payout to the host started but didn't finish",
  payout_overdue: "The event is over and the host is set up, but the fee hasn't been sent",
  credit_unsent: "A dispute was won but what the host is owed back wasn't sent",
  stripe_unreachable: "Couldn't check this payment with Stripe",
} as const;
export type PaymentIssueKind = keyof typeof paymentIssueLabels;

/** An open problem with one payment, for staff. */
export interface PaymentIssueView {
  /** The charge's id (a Checkout Session or PaymentIntent id). */
  id: string;
  tournamentId: string;
  hostId: string;
  payerId: string;
  label: string;
  kinds: PaymentIssueKind[];
  /** What was compared, e.g. "Stripe: refunded $400; here: paid". */
  detail: string;
  firstSeenAt: string | null;
  lastSeenAt: string | null;
}

/** One payment through Stall 10, for staff. Ids only, never card or bank details. */
export interface StaffChargeView {
  id: string;
  tournamentId: string;
  hostId: string;
  payerId: string;
  payerKind: string;
  label: string;
  /** open, processing, paid, failed, expired, refunding, refunded, disputed, duplicate. */
  status: string;
  amountCents: number;
  baseCents: number;
  processingCents: number;
  released: boolean;
  kept: boolean;
  transferCents: number;
  refundCents: number;
  reversed: boolean;
  owedCents: number;
  createdAt: string | null;
  paidAt: string | null;
  releasedAt: string | null;
  refundedAt: string | null;
}

/** GET /v1/staff/payments (staff): open problems first, then the latest payments. */
export interface StaffPaymentsView {
  available: boolean;
  issues: PaymentIssueView[];
  /** The latest 100, newest first; ?tournament= narrows them to one event. */
  charges: StaffChargeView[];
  /** When the last check against Stripe ran (ISO), if ever. */
  checkedAt: string | null;
}

/** POST /v1/payments/reconcile (staff) or the daily job: the check against Stripe. */
export interface ReconcileResult {
  checked: number;
  /** Payments with a problem now. */
  issues: number;
  /** Problems found earlier that are fixed now. */
  resolved: number;
}

/** Setting up or changing payouts needs a sign-in in the last 15 minutes (so a left-open session can't move a host's money). */
export const payoutsReauthMessage = "For your security, sign out and sign in again, then set up or change payouts within 15 minutes.";

export const paymentPaths = {
  payouts: (teamId: string) => `/v1/teams/${teamId}/payouts`,
  payoutLink: (teamId: string) => `/v1/teams/${teamId}/payouts/link`,
  payoutSession: (teamId: string) => `/v1/teams/${teamId}/payouts/session`,
  payOptions: (tournamentId: string) => `/v1/tournaments/${tournamentId}/pay`,
  checkout: (tournamentId: string) => `/v1/tournaments/${tournamentId}/checkout`,
  intent: (tournamentId: string) => `/v1/tournaments/${tournamentId}/pay/intent`,
  offline: (tournamentId: string) => `/v1/tournaments/${tournamentId}/pay/offline`,
  mark: (tournamentId: string, payerId: string) => `/v1/tournaments/${tournamentId}/payments/${payerId}`,
  refund: (tournamentId: string, payerId: string) => `/v1/tournaments/${tournamentId}/payments/${payerId}/refund`,
  earnings: (teamId: string) => `/v1/teams/${teamId}/earnings`,
  release: "/v1/payments/release",
  reconcile: "/v1/payments/reconcile",
  staff: "/v1/staff/payments",
  /** Cloud Scheduler only (a Google-signed token from the scheduler's service account). */
  jobRelease: "/v1/jobs/payments/release",
  jobReconcile: "/v1/jobs/payments/reconcile",
  fees: "/v1/payments/fees",
  webhook: "/v1/payments/stripe/webhook",
} as const;
