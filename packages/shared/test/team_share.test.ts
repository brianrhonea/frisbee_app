// Splitting a team fee (team_share.ts); the app's team_share_test.dart
// checks evenShare and shareTotals the same way.
import { describe, expect, it } from "vitest";
import { evenShare, markSharePaidRequestSchema, setTeamShareRequestSchema, shareTotals } from "../src/index.js";

describe("team fee split", () => {
  it("rounds an even share up to the cent", () => {
    expect(evenShare(10000, 3)).toBe(3334);
    expect(evenShare(16000, 4)).toBe(4000);
    expect(evenShare(0, 3)).toBe(0);
    expect(evenShare(100, 0)).toBe(0);
  });
  it("adds up what's in and what's owed", () => {
    expect(shareTotals(4000, [{ paid: true }, { paid: false }])).toEqual({ paid: 1, owed: 1, collectedCents: 4000, outstandingCents: 4000 });
  });
  it("checks the requests", () => {
    expect(setTeamShareRequestSchema.parse({ amountCents: 4000 })).toEqual({ amountCents: 4000, currency: "usd", note: "" });
    expect(setTeamShareRequestSchema.safeParse({ amountCents: 0 }).success).toBe(false);
    expect(setTeamShareRequestSchema.safeParse({ amountCents: 4000, extra: 1 }).success).toBe(false);
    expect(markSharePaidRequestSchema.safeParse({ paid: "yes" }).success).toBe(false);
  });
});
