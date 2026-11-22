// Online payments for tournament and league fees (Stripe Connect).
//
// A host (the team or community running the event) connects its own
// Stripe account once; teams then pay their bid or spot fee, and players
// their entry fee, through Stripe Checkout. Each payment is a direct
// charge on the host's account: the host pays Stripe's card fee and keeps
// the rest, minus Stall 10's platform fee (PlatformFee). Paying marks the
// same `tournaments/{id}/payments/{payerId}` record the host can still set
// by hand, so instructions-and-mark-paid keeps working beside it.
import { z } from "zod";

/** Stall 10's cut of each payment: a percentage (basis points) plus a fixed amount. */
export interface PlatformFee {
  /** 100 = 1%. */
  percentBps: number;
  fixedCents: number;
}

/** 1% + $1 (docs/product-spec.md §7). The API reads PLATFORM_FEE_BPS / PLATFORM_FEE_FIXED_CENTS. */
export const defaultPlatformFee: PlatformFee = { percentBps: 100, fixedCents: 100 };

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

/**
 * What to charge so that [amountCents] reaches the host after Stall 10's
 * fee and Stripe's card fee: the smallest charge whose breakdown leaves the
 * host at least [amountCents]. The payer sees the difference as a
 * processing fee. The same for every payment method (a cheaper bank
 * payment leaves the host a little more), so it's never a card surcharge.
 */
export function chargeCoveringFees(amountCents: number, platform: PlatformFee, card: PlatformFee = stripeCardFeeEstimate): number {
  if (amountCents <= 0) return amountCents;
  const rate = (platform.percentBps + card.percentBps) / 10_000;
  let charge = Math.max(amountCents, Math.floor((amountCents + platform.fixedCents + card.fixedCents) / (1 - rate)) - 2);
  while (feeBreakdown(charge, platform, card).hostCents < amountCents) charge++;
  return charge;
}

/** What a payer is charged online for [fee]: the fee, plus the fees when the host passes them on. */
export function onlineCharge(fee: { amountCents: number; payerCoversFees?: boolean }, platform: PlatformFee, card: PlatformFee = stripeCardFeeEstimate): { chargeCents: number; processingCents: number; platformCents: number } {
  const chargeCents = fee.payerCoversFees === true ? chargeCoveringFees(fee.amountCents, platform, card) : fee.amountCents;
  return { chargeCents, processingCents: chargeCents - fee.amountCents, platformCents: chargeCents > 0 ? platformFeeCents(chargeCents, platform) : 0 };
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

/** GET /v1/teams/:teamId/payouts: the host's payout account (owners only). */
export interface PayoutAccountView {
  /** false: online payments aren't set up on this server; hide the section. */
  available: boolean;
  /** none: not connected; pending: Stripe still needs details; ready: can take payments. */
  status: PayoutStatus;
  /** Stall 10's fee, e.g. "1% + $1". */
  feeLabel: string;
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
  /** What paying online costs: [amountCents], plus [processingCents] when the host passes the fees on. */
  chargeCents: number;
  /** The processing fee added for the payer (0 unless the host passes the fees on). */
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
  })
  .refine((r) => (r.payer === "team") === (r.teamId !== undefined), { message: "Say which team is paying." });
export type CheckoutRequest = z.infer<typeof checkoutRequestSchema>;

/** The Stripe Checkout page to open. */
export interface CheckoutResult {
  url: string;
}

/** The note set on the payment record when Stripe confirms it. */
export const paidOnlineNote = "Paid online through Stall 10";
/** The note set when the host refunds it in Stripe. */
export const refundedOnlineNote = "Refunded through Stripe";

export const paymentPaths = {
  payouts: (teamId: string) => `/v1/teams/${teamId}/payouts`,
  payoutLink: (teamId: string) => `/v1/teams/${teamId}/payouts/link`,
  payOptions: (tournamentId: string) => `/v1/tournaments/${tournamentId}/pay`,
  checkout: (tournamentId: string) => `/v1/tournaments/${tournamentId}/checkout`,
  offline: (tournamentId: string) => `/v1/tournaments/${tournamentId}/pay/offline`,
  mark: (tournamentId: string, payerId: string) => `/v1/tournaments/${tournamentId}/payments/${payerId}`,
  fees: "/v1/payments/fees",
  webhook: "/v1/payments/stripe/webhook",
} as const;
