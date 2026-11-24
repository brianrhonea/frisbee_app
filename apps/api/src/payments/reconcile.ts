// The daily check of Stall 10's records against Stripe (Stall 10 collects
// every fee and pays hosts out): for one charge doc, what Stripe says about
// its payment and, once sent, its transfer. Pure, so it's tested on its
// own; PaymentService.reconcile reads the docs, asks Stripe and records
// what it finds in paymentIssues/{charge} for staff.
import type { PaymentIssueKind } from "@stall10/shared";
import type { GatewayPaymentSummary, GatewayTransferSummary } from "./gateway.js";

type Data = Record<string, unknown>;

const cents = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.round(v) : 0);
const money = (c: number) => `$${(c / 100).toFixed(2)}`;

/** Statuses that mean Stripe took the money (and may have given some back). */
const takenStatuses = new Set(["paid", "refunding", "refunded", "disputed", "duplicate"]);

/** A charge doc's own story, the part the check compares. */
export interface ChargeFacts {
  status: string;
  amountCents: number;
  refundCents: number;
  released: boolean;
  kept: boolean;
  transfer: string;
  transferCents: number;
  destination: string;
  reversed: boolean;
  owedCents: number;
  /** A transfer was planned but not confirmed (charge.release set). */
  releasePending: boolean;
}

export function chargeFacts(c: Data): ChargeFacts {
  return {
    status: typeof c.status === "string" ? c.status : "",
    amountCents: cents(c.amountCents),
    refundCents: cents(c.refundCents) || cents(c.amountRefundedCents),
    released: c.released === true,
    kept: c.kept === true,
    transfer: typeof c.transfer === "string" ? c.transfer : "",
    transferCents: cents(c.transferCents),
    destination: typeof c.destination === "string" ? c.destination : "",
    reversed: c.reversed === true,
    owedCents: cents(c.owedCents),
    releasePending: !!c.release && typeof c.release === "object",
  };
}

export interface CheckResult {
  kinds: PaymentIssueKind[];
  detail: string[];
}

/**
 * What's wrong with [c] given Stripe's [payment] (and [transfer] once one
 * was sent). [stuckRelease]: the planned transfer is old enough that it
 * should have finished.
 */
export function checkCharge(c: ChargeFacts, payment: GatewayPaymentSummary, transfer: GatewayTransferSummary | null, stuckRelease = false): CheckResult {
  const kinds: PaymentIssueKind[] = [];
  const detail: string[] = [];
  const add = (k: PaymentIssueKind, d: string) => {
    if (!kinds.includes(k)) kinds.push(k);
    detail.push(d);
  };
  const taken = takenStatuses.has(c.status);
  if (taken && payment.status !== "succeeded") add("not_paid_on_stripe", `Stripe: ${payment.status}; here: ${c.status}`);
  if (!taken && payment.status === "succeeded") add("paid_not_recorded", `Stripe: succeeded; here: ${c.status || "no status"}`);
  if (payment.status === "succeeded" && c.amountCents > 0 && payment.amountCents !== c.amountCents) {
    add("amount_mismatch", `Stripe charged ${money(payment.amountCents)}; here: ${money(c.amountCents)}`);
  }
  if (payment.refundedCents > 0 && c.status !== "refunded" && c.status !== "refunding" && c.status !== "duplicate") {
    add("refund_not_recorded", `Stripe refunded ${money(payment.refundedCents)}; here: ${c.status}`);
  }
  if (c.status === "refunded" && payment.refundedCents < c.refundCents) {
    add("refund_missing", `Refunded here: ${money(c.refundCents)}; on Stripe: ${money(payment.refundedCents)}`);
  }
  if ((payment.dispute === "open" || payment.dispute === "lost") && c.status !== "disputed") {
    add("dispute_not_recorded", `Stripe dispute: ${payment.dispute}; here: ${c.status}`);
  }
  if (payment.dispute === "won" && c.status === "disputed") add("dispute_won_not_recorded", "Stripe dispute: won; here: disputed");
  if (c.released && !c.kept && c.transferCents > 0) {
    if (!c.transfer || !transfer) {
      add("transfer_missing", `Sent here: ${money(c.transferCents)}; no transfer on Stripe`);
    } else {
      if (transfer.amountCents !== c.transferCents || (c.destination && transfer.destination !== c.destination)) {
        add("transfer_mismatch", `Transfer on Stripe: ${money(transfer.amountCents)} to ${transfer.destination}; here: ${money(c.transferCents)} to ${c.destination}`);
      }
      // Reversed here without a shortfall: Stripe must have it back.
      if (c.reversed && c.owedCents === 0 && transfer.reversedCents < c.transferCents) {
        add("reversal_missing", `Taken back here: ${money(c.transferCents)}; reversed on Stripe: ${money(transfer.reversedCents)}`);
      }
    }
  }
  if (c.releasePending && stuckRelease) add("release_stuck", "A transfer to the host was started but not confirmed");
  return { kinds, detail };
}
