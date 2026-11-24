// The daily check's comparison of one charge doc with what Stripe says
// (src/payments/reconcile.ts).
import { describe, expect, it } from "vitest";
import type { GatewayPaymentSummary } from "../src/payments/gateway.js";
import { chargeFacts, checkCharge } from "../src/payments/reconcile.js";

const stripe = (patch: Partial<GatewayPaymentSummary> = {}): GatewayPaymentSummary => ({ status: "succeeded", amountCents: 42461, refundedCents: 0, dispute: "none", ...patch });
const charge = (patch: Record<string, unknown> = {}) => chargeFacts({ status: "paid", amountCents: 42461, baseCents: 40000, ...patch });
const kinds = (...args: Parameters<typeof checkCharge>) => checkCharge(...args).kinds;

describe("checking one payment against Stripe", () => {
  it("finds nothing when both agree", () => {
    expect(kinds(charge(), stripe(), null)).toEqual([]);
    expect(kinds(charge({ status: "refunded", refundCents: 40000 }), stripe({ refundedCents: 40000 }), null)).toEqual([]);
    expect(kinds(charge({ status: "expired" }), stripe({ status: "canceled" }), null)).toEqual([]);
    expect(kinds(charge({ status: "disputed" }), stripe({ dispute: "lost" }), null)).toEqual([]);
  });

  it("finds payments that disagree about being paid", () => {
    expect(kinds(charge(), stripe({ status: "open" }), null)).toEqual(["not_paid_on_stripe"]);
    expect(kinds(charge({ status: "expired" }), stripe(), null)).toEqual(["paid_not_recorded"]);
    expect(kinds(charge(), stripe({ amountCents: 100 }), null)).toEqual(["amount_mismatch"]);
  });

  it("finds refunds and disputes recorded on one side only", () => {
    expect(kinds(charge(), stripe({ refundedCents: 40000 }), null)).toEqual(["refund_not_recorded"]);
    expect(kinds(charge({ status: "refunded", refundCents: 40000 }), stripe(), null)).toEqual(["refund_missing"]);
    expect(kinds(charge(), stripe({ dispute: "open" }), null)).toEqual(["dispute_not_recorded"]);
    expect(kinds(charge({ status: "disputed" }), stripe({ dispute: "won" }), null)).toEqual(["dispute_won_not_recorded"]);
  });

  it("checks the transfer to the host once it's sent", () => {
    const sent = { released: true, transfer: "tr_1", transferCents: 40000, destination: "acct_1" };
    const transfer = { destination: "acct_1", amountCents: 40000, reversedCents: 0 };
    expect(kinds(charge(sent), stripe(), transfer)).toEqual([]);
    expect(kinds(charge(sent), stripe(), null)).toEqual(["transfer_missing"]);
    expect(kinds(charge(sent), stripe(), { ...transfer, destination: "acct_2" })).toEqual(["transfer_mismatch"]);
    expect(kinds(charge(sent), stripe(), { ...transfer, amountCents: 1 })).toEqual(["transfer_mismatch"]);
    // Taken back: Stripe must show the reversal, unless it was left owed.
    const back = { ...sent, status: "refunded", refundCents: 40000, reversed: true };
    expect(kinds(charge(back), stripe({ refundedCents: 40000 }), transfer)).toEqual(["reversal_missing"]);
    expect(kinds(charge(back), stripe({ refundedCents: 40000 }), { ...transfer, reversedCents: 40000 })).toEqual([]);
    expect(kinds(charge({ ...back, owedCents: 40000 }), stripe({ refundedCents: 40000 }), transfer)).toEqual([]);
    // Stall 10's own event: nothing was transferred.
    expect(kinds(charge({ released: true, kept: true }), stripe(), null)).toEqual([]);
  });

  it("finds a transfer that started but never finished, once it's old", () => {
    const pending = charge({ release: { n: 1, cents: 40000, destination: "acct_1" } });
    expect(kinds(pending, stripe(), null, false)).toEqual([]);
    expect(kinds(pending, stripe(), null, true)).toEqual(["release_stuck"]);
  });

  it("says what it compared, in dollars", () => {
    expect(checkCharge(charge(), stripe({ refundedCents: 40000 }), null).detail).toEqual(["Stripe refunded $400.00; here: paid"]);
  });
});
