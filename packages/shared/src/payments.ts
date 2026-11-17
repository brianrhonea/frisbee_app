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

/** Who is paying a tournament fee. */
export const payerKinds = ["team", "player"] as const;
export type PayerKind = (typeof payerKinds)[number];

/** GET /v1/tournaments/:id/pay?team=…: whether the caller can pay this fee online. */
export interface PayOptions {
  /** The host takes payments through Stall 10 and this fee can be paid online. */
  online: boolean;
  amountCents: number;
  currency: string;
  /** Stall 10's part of it (included in the amount, not added). */
  feeCents: number;
  feeLabel: string;
  /** Already paid (online or marked by the host). */
  paid: boolean;
  /** Why it can't be paid online, when [online] is false and it isn't paid. */
  reason: string | null;
}

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
  webhook: "/v1/payments/stripe/webhook",
} as const;
