import { describe, expect, it } from "vitest";
import { chargeCoveringFees, defaultPlatformFee, feeBreakdown, onlineCharge, platformFeeLabel, stripeCardFeeEstimate } from "../src/index.js";

describe("feeBreakdown: where a fee paid online goes", () => {
  it("splits $100 into Stall 10's $2, Stripe's $3.20 and the host's $94.80", () => {
    expect(feeBreakdown(10_000, defaultPlatformFee)).toEqual({ amountCents: 10_000, platformCents: 200, stripeCents: 320, hostCents: 9_480 });
  });

  it("rounds each fee to the cent", () => {
    // $37.50: 1% = 37.5¢ → 38¢ + $1; 2.9% = 108.75¢ → 109¢ + 30¢.
    expect(feeBreakdown(3_750, defaultPlatformFee)).toEqual({ amountCents: 3_750, platformCents: 138, stripeCents: 139, hostCents: 3_473 });
  });

  it("never leaves the host less than nothing", () => {
    expect(feeBreakdown(100, defaultPlatformFee).hostCents).toBe(0);
  });

  it("reads Stripe's rate as people say it", () => {
    expect(platformFeeLabel(stripeCardFeeEstimate)).toBe("2.9% + $0.30");
  });
});

describe("chargeCoveringFees: the host gets the whole fee", () => {
  it("adds just enough for Stall 10's and Stripe's fees", () => {
    // Same cases as apps/mobile/test/ui/payments_test.dart.
    expect(chargeCoveringFees(10_000, defaultPlatformFee)).toBe(10_541);
    expect(chargeCoveringFees(40_000, defaultPlatformFee)).toBe(41_759);
    expect(feeBreakdown(10_541, defaultPlatformFee).hostCents).toBe(10_000);
    expect(onlineCharge({ amountCents: 10_000, payerCoversFees: true }, defaultPlatformFee)).toEqual({ chargeCents: 10_541, processingCents: 541, platformCents: 205 });
    expect(onlineCharge({ amountCents: 10_000 }, defaultPlatformFee).processingCents).toBe(0);
  });
});
