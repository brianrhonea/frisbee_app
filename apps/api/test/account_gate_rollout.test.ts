// The account gate's rollout controls: the report-only switch
// (ACCOUNT_GATE_MODE), no-op claim writes (F4) and the startup checks (F8).
import { describe, expect, it } from "vitest";
import { mergedClaims, setMergedClaims, type ClaimsAuth } from "../src/account/claims.js";
import { buildApp } from "../src/app.js";
import { accountGateModeFromEnv, assertStartupEnvironment, DEV_PROJECT_ID, PROD_PROJECT_ID, StartupConfigError } from "../src/startup_env.js";
import { FakeCipher, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12);

describe("report-only mode", () => {
  function setup(mode: "report" | "enforce") {
    const logged: Array<Record<string, unknown>> = [];
    const app = buildApp({
      verifier: new FakeVerifier(),
      users: new FakeUsers(),
      teams: new FakeTeamRepository(),
      store: new FakeStore(() => now),
      personal: new FakeCipher(),
      now: () => now,
      writeLimits: false,
      accountGateMode: mode,
      // Capture what the gate logs (pino's logMethod hook), without printing it.
      logger: {
        level: "warn",
        hooks: {
          logMethod(args) {
            if (args[0] && typeof args[0] === "object") logged.push(args[0] as Record<string, unknown>);
          },
        },
      },
    });
    const call = (kind: string, url: string) => app.inject({ method: "POST", url, payload: {}, headers: { authorization: `Bearer ${kind}:u1` } });
    return { call, logged };
  }

  it("lets an incomplete account's write reach its handler (no account_incomplete) in report mode", async () => {
    const s = setup("report");
    const res = await s.call("bare", "/v1/posts");
    expect(res.body).not.toContain("account_incomplete");
  });

  it("enforce mode still refuses the same write", async () => {
    const res = await setup("enforce").call("bare", "/v1/posts");
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe("account_incomplete");
  });

  it("report mode does not log for a complete account", async () => {
    const s = setup("report");
    await s.call("token", "/v1/posts");
    expect(s.logged.filter((l) => l.event === "account_incomplete")).toEqual([]);
  });

  it("report mode logs what would have been refused, with the missing fields and no body", async () => {
    const s = setup("report");
    await s.call("noterms", "/v1/posts");
    const entry = s.logged.find((l) => l.event === "account_incomplete");
    expect(entry).toMatchObject({ mode: "report", uid: "u1", missing: ["terms"], route: "POST /v1/posts" });
  });
});

describe("ACCOUNT_GATE_MODE", () => {
  it("defaults to report-only, and accepts either value in any case", () => {
    expect(accountGateModeFromEnv({})).toBe("report");
    expect(accountGateModeFromEnv({ ACCOUNT_GATE_MODE: "  " })).toBe("report");
    expect(accountGateModeFromEnv({ ACCOUNT_GATE_MODE: "ENFORCE" })).toBe("enforce");
    expect(accountGateModeFromEnv({ ACCOUNT_GATE_MODE: "report" })).toBe("report");
  });

  it("a typo is a startup error, so it can't quietly turn the gate off", () => {
    expect(() => accountGateModeFromEnv({ ACCOUNT_GATE_MODE: "enforced" })).toThrow(StartupConfigError);
    expect(() => assertStartupEnvironment({ ACCOUNT_GATE_MODE: "off" })).toThrow(/ACCOUNT_GATE_MODE/);
  });
});

describe("startup with the gate enforcing (F8)", () => {
  const kms = { PERSONAL_DETAILS_KMS_KEY: "projects/p/locations/l/keyRings/r/cryptoKeys/k" };
  it("refuses to start without a cipher", () => {
    expect(() => assertStartupEnvironment({ ACCOUNT_GATE_MODE: "enforce" })).toThrow(/PERSONAL_DETAILS_KMS_KEY.*ACCOUNT_GATE_MODE=enforce/);
    expect(() => assertStartupEnvironment({ ACCOUNT_GATE_MODE: "enforce", PERSONAL_DETAILS_KMS_KEY: " " })).toThrow(StartupConfigError);
  });
  it("starts with the KMS key, or a local key (emulators)", () => {
    expect(assertStartupEnvironment({ ACCOUNT_GATE_MODE: "enforce", ...kms })).toBe(DEV_PROJECT_ID);
    expect(assertStartupEnvironment({ ACCOUNT_GATE_MODE: "enforce", PERSONAL_DETAILS_LOCAL_KEY: "k", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080" })).toBe(DEV_PROJECT_ID);
    expect(assertStartupEnvironment({ ACCOUNT_GATE_MODE: "enforce", NODE_ENV: "production", FIREBASE_PROJECT_ID: PROD_PROJECT_ID, ...kms })).toBe(PROD_PROJECT_ID);
  });
  it("report-only starts locally without one, deployed still needs it", () => {
    expect(assertStartupEnvironment({})).toBe(DEV_PROJECT_ID);
    expect(() => assertStartupEnvironment({ NODE_ENV: "production", FIREBASE_PROJECT_ID: DEV_PROJECT_ID })).toThrow(/PERSONAL_DETAILS_KMS_KEY/);
  });
  it("never puts a value in the message", () => {
    try {
      assertStartupEnvironment({ ACCOUNT_GATE_MODE: "enforce", STRIPE_SECRET_KEY: "sk_test_secretvalue" });
    } catch (e) {
      expect((e as Error).message).not.toContain("secretvalue");
    }
  });
});

describe("claim writes (F4)", () => {
  function fakeAuth(initial: Record<string, unknown> | null) {
    const calls = { get: 0, set: [] as Array<Record<string, unknown>> };
    let claims = initial;
    const auth: ClaimsAuth = {
      async getUser() {
        calls.get++;
        return { customClaims: claims };
      },
      async setCustomUserClaims(_uid, c) {
        calls.set.push(c);
        claims = c;
      },
    };
    return { auth, calls };
  }

  it("merges into the existing claims, so staff stays", () => {
    expect(mergedClaims({ staff: true }, { ageOk: true })).toEqual({ staff: true, ageOk: true });
    expect(mergedClaims(null, { terms: 1 })).toEqual({ terms: 1 });
  });
  it("returns null when every claim already holds", () => {
    expect(mergedClaims({ ageOk: true, terms: 1, staff: true }, { ageOk: true, terms: 1 })).toBeNull();
    expect(mergedClaims({ terms: 1 }, { terms: 2 })).not.toBeNull();
  });
  it("skips the Auth write when nothing would change", async () => {
    const { auth, calls } = fakeAuth({ ageOk: true, terms: 1 });
    expect(await setMergedClaims(auth, "u1", { ageOk: true })).toBe(false);
    expect(calls.set).toEqual([]);
  });
  it("writes once, then a repeat is a no-op", async () => {
    const { auth, calls } = fakeAuth({ staff: true });
    expect(await setMergedClaims(auth, "u1", { ageOk: true })).toBe(true);
    expect(await setMergedClaims(auth, "u1", { ageOk: true })).toBe(false);
    expect(calls.set).toEqual([{ staff: true, ageOk: true }]);
  });
});
