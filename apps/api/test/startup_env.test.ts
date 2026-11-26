// Startup environment assertions (INF-6) and the API with payments off
// (INF-8): no Stripe environment at all must boot and refuse cleanly.
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { stripeFromEnv } from "../src/payments/stripe.js";
import { assertStartupEnvironment, DEV_PROJECT_ID, isDeployed, PROD_PROJECT_ID, StartupConfigError, stripeKeyMode } from "../src/startup_env.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const kms = { PERSONAL_DETAILS_KMS_KEY: "projects/p/locations/l/keyRings/r/cryptoKeys/k", ACCOUNT_GATE_MODE: "enforce" };
const fails = (env: Record<string, string>, re: RegExp) => expect(() => assertStartupEnvironment(env)).toThrow(re);

describe("startup environment", () => {
  it("local dev works with no environment and defaults to the dev project", () => {
    expect(assertStartupEnvironment({})).toBe(DEV_PROJECT_ID);
    expect(isDeployed({})).toBe(false);
    expect(assertStartupEnvironment({ STRIPE_SECRET_KEY: "sk_test_x" })).toBe(DEV_PROJECT_ID);
    expect(assertStartupEnvironment({ FIREBASE_PROJECT_ID: "demo-stall10" })).toBe("demo-stall10");
  });

  it("deployed (NODE_ENV=production or Cloud Run) without FIREBASE_PROJECT_ID fails", () => {
    fails({ NODE_ENV: "production" }, /FIREBASE_PROJECT_ID must be set/);
    fails({ K_SERVICE: "api" }, /FIREBASE_PROJECT_ID must be set/);
    fails({ NODE_ENV: "production", FIREBASE_PROJECT_ID: "  " }, /FIREBASE_PROJECT_ID must be set/);
    expect(() => assertStartupEnvironment({ NODE_ENV: "production" })).toThrow(StartupConfigError);
  });

  it("deployed with the project set, with or without Stripe, boots", () => {
    expect(assertStartupEnvironment({ ...kms, K_SERVICE: "api", FIREBASE_PROJECT_ID: PROD_PROJECT_ID })).toBe(PROD_PROJECT_ID);
    expect(assertStartupEnvironment({ ...kms, NODE_ENV: "production", FIREBASE_PROJECT_ID: DEV_PROJECT_ID, STRIPE_SECRET_KEY: "rk_test_x" })).toBe(DEV_PROJECT_ID);
    expect(assertStartupEnvironment({ ...kms, NODE_ENV: "production", FIREBASE_PROJECT_ID: PROD_PROJECT_ID, STRIPE_SECRET_KEY: "rk_live_x" })).toBe(PROD_PROJECT_ID);
  });

  it("deployed without the personal-details KMS key fails, unless emulated; local runs need none", () => {
    fails({ NODE_ENV: "production", FIREBASE_PROJECT_ID: DEV_PROJECT_ID }, /PERSONAL_DETAILS_KMS_KEY must be set/);
    fails({ K_SERVICE: "api", FIREBASE_PROJECT_ID: PROD_PROJECT_ID, PERSONAL_DETAILS_KMS_KEY: "  " }, /PERSONAL_DETAILS_KMS_KEY must be set/);
    expect(assertStartupEnvironment({ NODE_ENV: "production", FIREBASE_PROJECT_ID: DEV_PROJECT_ID, FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080" })).toBe(DEV_PROJECT_ID);
    expect(assertStartupEnvironment({ FIREBASE_PROJECT_ID: DEV_PROJECT_ID })).toBe(DEV_PROJECT_ID);
  });

  it("a live key with a non-production project fails, even locally", () => {
    fails({ FIREBASE_PROJECT_ID: DEV_PROJECT_ID, STRIPE_SECRET_KEY: "sk_live_x" }, /live key/);
    fails({ STRIPE_SECRET_KEY: "rk_live_x" }, /live key/);
  });

  it("a test key with the production project fails", () => {
    fails({ FIREBASE_PROJECT_ID: PROD_PROJECT_ID, STRIPE_SECRET_KEY: "sk_test_x" }, /test key/);
    fails({ FIREBASE_PROJECT_ID: PROD_PROJECT_ID, STRIPE_SECRET_KEY: "rk_test_x" }, /test key/);
  });

  it("an unrecognised key fails when deployed only", () => {
    fails({ ...kms, NODE_ENV: "production", FIREBASE_PROJECT_ID: DEV_PROJECT_ID, STRIPE_SECRET_KEY: "whsec_nope" }, /isn't a Stripe/);
    expect(assertStartupEnvironment({ STRIPE_SECRET_KEY: "whsec_nope" })).toBe(DEV_PROJECT_ID);
    expect(stripeKeyMode("sk_live_a")).toBe("live");
    expect(stripeKeyMode("junk")).toBe("unknown");
  });

  it("never puts the key in the message", () => {
    const secret = "sk_live_SUPERSECRETVALUE";
    try {
      assertStartupEnvironment({ FIREBASE_PROJECT_ID: DEV_PROJECT_ID, STRIPE_SECRET_KEY: secret });
      expect.unreachable();
    } catch (e) {
      expect((e as Error).message).not.toContain("SUPERSECRET");
    }
  });
});

describe("payments off: no Stripe environment", () => {
  // What server.ts builds with no Stripe variables set.
  const gateway = stripeFromEnv({});
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    store: new FakeStore(() => 0),
    now: () => 0,
    payments: gateway ? { gateway, fee: { percentBps: 300, fixedCents: 0 }, returnUrl: "https://site.test" } : undefined,
  });
  const as = (method: "GET" | "POST", url: string, payload?: object) =>
    app.inject({ method, url, payload, headers: { authorization: "Bearer token:owner" } });

  it("builds no gateway without the key and a webhook secret", () => {
    expect(gateway).toBeUndefined();
    expect(stripeFromEnv({ STRIPE_PLATFORM_WEBHOOK_SECRET: "whsec_x" })).toBeUndefined();
  });

  it("boots and reports payments unavailable", async () => {
    const res = await as("GET", "/v1/payments/fees");
    expect(res.statusCode).toBe(200);
    expect(res.json().available).toBe(false);
  });

  it("refuses Stripe's webhook cleanly: 412, nothing recorded", async () => {
    const res = await app.inject({ method: "POST", url: "/v1/payments/stripe/webhook", payload: "{}", headers: { "content-type": "application/json", "stripe-signature": "t=1,v1=00" } });
    expect(res.statusCode).toBe(412);
    expect(res.json().error.message).toMatch(/aren't set up/);
  });
});
