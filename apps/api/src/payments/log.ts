// The payment history: paymentLog/{autoId}, one entry per change to a fee's
// payment, never updated or deleted (server only; no client rule matches
// it, and deleting a tournament or team leaves it). It is the record for
// questions and disputes: who did what, when, how much, and Stripe's ids.
import { type DocStore, serverTime, type Tx } from "../store.js";

export const paymentLogActions = [
  "checkout_started",
  "paid_online",
  "bank_payment_processing",
  "payment_failed",
  "checkout_expired",
  "duplicate_payment",
  "duplicate_refunded",
  "refunded_by_host",
  "partly_refunded_by_host",
  "disputed",
  "marked_paid",
  "marked_unpaid",
  "paying_another_way",
  "not_paying_another_way",
  // Stall 10 collecting (0.47.0): the host's share sent, kept (Stall 10's
  // own events), taken back after a refund or dispute (or owed when it
  // couldn't be), and refunds through Stall 10 or Stripe's Dashboard.
  "released",
  "kept_by_stall10",
  "transfer_reversed",
  "owed_by_host",
  "refund_started",
  // An organizer's refund of a fee already paid out to the host's bank: refused, staff sort it out.
  "refund_blocked",
  // Staff approved a host's first (or a large) payout.
  "payout_approved",
  "refunded",
  "refunded_on_stripe",
  "dispute_won",
] as const;
export type PaymentLogAction = (typeof paymentLogActions)[number];

export interface PaymentLogEntry {
  tournamentId: string;
  /** The team's id, or the player's uid. */
  payerId: string;
  action: PaymentLogAction;
  /** The uid who did it, or "stripe" for what Stripe reported. */
  by: string;
  amountCents?: number;
  currency?: string;
  note?: string;
  /** Stripe's ids, for looking it up in the Dashboard (stripeAccount: a direct charge's host account). */
  stripeAccount?: string;
  checkoutSession?: string;
  paymentIntent?: string;
}

/** Adds [entry] in [tx], stamped with the server's time. */
export function logPayment(store: Pick<DocStore, "newId">, tx: Pick<Tx, "set">, entry: PaymentLogEntry): void {
  const clean = Object.fromEntries(Object.entries(entry).filter(([, v]) => v !== undefined && v !== ""));
  tx.set(`paymentLog/${store.newId("paymentLog")}`, { ...clean, at: serverTime });
}
