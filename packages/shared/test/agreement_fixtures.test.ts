// The agreement step (agreements.ts) against the app's
// (apps/mobile/lib/domain/models/agreement.dart), on fixtures/agreements
// (written by apps/mobile/test/shared_fixtures/agreement_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { agreementPoints, hasAgreed, termsVersion } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

describe("the guidelines and terms agreement matches the app (fixtures/agreements/terms.json)", () => {
  it("has the same version and summary", () => {
    const [c] = fixture<{ version: number; points: string[] }>("agreements/terms.json").cases;
    expect(c).toEqual({ version: termsVersion, points: [...agreementPoints] });
  });

  it("counts only an agreement to the current version", () => {
    expect(hasAgreed({ version: termsVersion })).toBe(true);
    expect(hasAgreed({ version: termsVersion - 1 })).toBe(false);
    expect(hasAgreed(undefined)).toBe(false);
    expect(hasAgreed({ version: "1" })).toBe(false);
  });
});
