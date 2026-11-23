import { describe, expect, it } from "vitest";
import { chargeCoveringFees, defaultPlatformFee, feeBreakdown, onlineCharge, platformFeeLabel, stripeCardFeeEstimate } from "../src/index.js";

describe("feeBreakdown: where a fee paid online goes", () => {
  it("splits $100 into Stall 10's $3, Stripe's $3.20 and the rest", () => {
    expect(feeBreakdown(10_000, defaultPlatformFee)).toEqual({ amountCents: 10_000, platformCents: 300, stripeCents: 320, hostCents: 9_380 });
  });

  it("rounds each fee to the cent", () => {
    // $37.50: 3% = 112.5¢ → 113¢; 2.9% = 108.75¢ → 109¢ + 30¢.
    expect(feeBreakdown(3_750, defaultPlatformFee)).toEqual({ amountCents: 3_750, platformCents: 113, stripeCents: 139, hostCents: 3_498 });
  });

  it("never leaves the host less than nothing", () => {
    expect(feeBreakdown(30, defaultPlatformFee).hostCents).toBe(0);
  });

  it("reads Stripe's rate as people say it", () => {
    expect(platformFeeLabel(stripeCardFeeEstimate)).toBe("2.9% + $0.30");
  });
});

describe("onlineCharge: the payer pays the fees, the host gets the whole fee", () => {
  it("is 3% of the fee for Stall 10", () => {
    expect(defaultPlatformFee).toEqual({ percentBps: 300, fixedCents: 0 });
    expect(platformFeeLabel(defaultPlatformFee)).toBe("3%");
  });

  it("adds Stall 10's 3% of the fee and just enough for Stripe's fee on the whole charge", () => {
    // Same cases as apps/mobile/test/ui/payments_test.dart.
    expect(onlineCharge({ amountCents: 10_000 }, defaultPlatformFee)).toEqual({ chargeCents: 10_639, processingCents: 639, platformCents: 300 });
    expect(onlineCharge({ amountCents: 40_000 }, defaultPlatformFee)).toEqual({ chargeCents: 42_461, processingCents: 2_461, platformCents: 1_200 });
    expect(chargeCoveringFees(40_000, defaultPlatformFee)).toBe(42_461);
    for (const amount of [50, 999, 3_750, 6_000, 10_000, 40_000, 123_457]) {
      const c = onlineCharge({ amountCents: amount }, defaultPlatformFee);
      const stripe = Math.round((c.chargeCents * stripeCardFeeEstimate.percentBps) / 10_000) + stripeCardFeeEstimate.fixedCents;
      const host = c.chargeCents - c.platformCents - stripe;
      // The whole fee, and not a cent more than rounding needs.
      expect(host).toBeGreaterThanOrEqual(amount);
      expect(host).toBeLessThanOrEqual(amount + 1);
    }
  });

  it("always: an old event's payerCoversFees switch changes nothing", () => {
    const old = { amountCents: 10_000, payerCoversFees: false } as { amountCents: number };
    expect(onlineCharge(old, defaultPlatformFee).chargeCents).toBe(10_639);
  });

  it("nothing for a free event", () => {
    expect(onlineCharge({ amountCents: 0 }, defaultPlatformFee)).toEqual({ chargeCents: 0, processingCents: 0, platformCents: 0 });
  });
});
