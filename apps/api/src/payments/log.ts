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
  /** Stripe's ids, for looking it up in the host's Dashboard. */
  stripeAccount?: string;
  checkoutSession?: string;
  paymentIntent?: string;
}

/** Adds [entry] in [tx], stamped with the server's time. */
export function logPayment(store: Pick<DocStore, "newId">, tx: Pick<Tx, "set">, entry: PaymentLogEntry): void {
  const clean = Object.fromEntries(Object.entries(entry).filter(([, v]) => v !== undefined && v !== ""));
  tx.set(`paymentLog/${store.newId("paymentLog")}`, { ...clean, at: serverTime });
}
