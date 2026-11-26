import { readFileSync } from "node:fs";
import { join } from "node:path";
import { HttpsError } from "firebase-functions/v2/https";
import { describe, expect, it } from "vitest";

import { currentTermsVersion, gateMessages, gateMissing, requireCompleteAccount } from "../../src/account/gate";

// The callables' account check (account gate F2) must say what the API says.
const full = { email_verified: true, ageOk: true, terms: currentTermsVersion };
const shared = join(__dirname, "../../../../packages/shared/src");

describe("the callables' account check", () => {
  it("passes a complete account", () => {
    expect(gateMissing({ token: full })).toEqual([]);
    expect(() => requireCompleteAccount({ token: full })).not.toThrow();
  });

  it.each([
    ["unverified email", { ...full, email_verified: false }, ["email_unverified"]],
    ["no email_verified claim", { ageOk: true, terms: currentTermsVersion }, ["email_unverified"]],
    ["no ageOk", { ...full, ageOk: undefined }, ["age"]],
    ["ageOk as a string", { ...full, ageOk: "true" }, ["age"]],
    ["ageOk false", { ...full, ageOk: false }, ["age"]],
    ["no terms", { ...full, terms: undefined }, ["terms"]],
    ["terms as a string", { ...full, terms: "1" }, ["terms"]],
    ["terms below the current version", { ...full, terms: currentTermsVersion - 1 }, ["terms"]],
    ["nothing", {}, ["email_unverified", "age", "terms"]],
  ])("refuses %s, naming what is missing in the API's order", (_, token, missing) => {
    expect(gateMissing({ token })).toEqual(missing);
    try {
      requireCompleteAccount({ token });
      throw new Error("did not throw");
    } catch (e) {
      expect(e).toBeInstanceOf(HttpsError);
      const err = e as HttpsError;
      expect(err.code).toBe("permission-denied");
      expect(err.message).toBe(gateMessages[missing[0] as keyof typeof gateMessages]);
      expect(err.details).toEqual({ code: "account_incomplete", fields: Object.fromEntries(missing.map((f) => [f, gateMessages[f as keyof typeof gateMessages]])) });
    }
  });

  it("a newer Terms version than the current one passes", () => {
    expect(gateMissing({ token: { ...full, terms: currentTermsVersion + 1 } })).toEqual([]);
  });

  it("stays in step with packages/shared: version and messages", () => {
    const terms = Number(/export const termsVersion = (\d+);/.exec(readFileSync(join(shared, "agreements.ts"), "utf8"))?.[1]);
    expect(currentTermsVersion).toBe(terms);
    const src = readFileSync(join(shared, "account_gate.ts"), "utf8");
    for (const text of Object.values(gateMessages)) expect(src).toContain(JSON.stringify(text));
  });
});

// Every callable that writes, or hands out access, runs the check before
// reading anything from the request.
describe("the gated callables call it", () => {
  const src = (f: string) => readFileSync(join(__dirname, "../../src", f), "utf8");
  const body = (file: string, name: string) => {
    const s = src(file);
    const start = s.indexOf(`export const ${name} = onCall`);
    expect(start).toBeGreaterThan(-1);
    return s.slice(start, start + 600);
  };
  it.each([
    ["meetings/functions.ts", "joinToken"],
    ["meetings/functions.ts", "voiceToken"],
    ["tournaments/callables.ts", "createLeagueTeams"],
  ])("%s %s", (file, name) => {
    expect(body(file, name)).toContain("requireCompleteAccount(req.auth!)");
  });
  it("every draft callable goes through the shared context(), which checks", () => {
    const s = src("tournaments/draft.ts");
    const ctx = s.slice(s.indexOf("async function context("), s.indexOf("async function context(") + 600);
    expect(ctx).toContain("requireCompleteAccount(req.auth!)");
    for (const name of ["startDraft", "draftPick", "draftControl", "finishDraft"]) {
      expect(body("tournaments/draft.ts", name)).toContain("await context(req)");
    }
  });
});
