// Account gate re-check fixes (#3a-S2): N1 photo name strictness, N2 profile
// pictures passed through the trust check, N3 explicit gate mode when
// deployed, N4 a lifted suspension never re-enables an under-13 account.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { configurePhotoTrust, trustedPhotoUrl, trustedProfilePhoto } from "../src/media/photo_url.js";
import { reportId } from "../src/moderation/service.js";
import { accountGateModeFromEnv, assertStartupEnvironment, DEV_PROJECT_ID, StartupConfigError } from "../src/startup_env.js";
import type { PersonalCipher } from "../src/personal/cipher.js";
import { FakeCipher, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12);
const bucket = "proj.firebasestorage.app";
const ownUrl = (uid: string, file: string) => `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/users%2F${uid}%2Fprofile%2F${file}?alt=media&token=3f2c9a1e-7b4d-4c58-9e0a-1d2b3c4d5e6f`;
const evil = "https://evil.example/pixel.gif";

beforeEach(() => configurePhotoTrust([bucket]));

describe("N1: the file name is strict", () => {
  it("accepts what the API writes (<uploadId>.<ext>?alt=media&token=<uuid>)", () => {
    const url = ownUrl("u1", "0f8fad5b-d9cb-469f-a165-70867728950e.jpg");
    expect(trustedPhotoUrl(url, "u1", [bucket])).toBe(url);
  });
  it.each([["..\\x"], [".."], ["..x.jpg"], [".hidden"], ["a%5Cb.jpg"], ["a%2Fb.jpg"], ["a b.jpg"]])("refuses the name %s", (name) => {
    expect(trustedPhotoUrl(ownUrl("u1", name), "u1", [bucket])).toBeNull();
  });
});

describe("N2: a profile's picture is judged like the Auth photoURL", () => {
  function setup() {
    const store = new FakeStore(() => now);
    const users = new FakeUsers();
    const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, now: () => now });
    const call = (method: "POST" | "PUT", url: string, body?: object, uid = "me") =>
      app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer token:${uid}` } });
    return { store, users, call };
  }

  it("trustedProfilePhoto keeps the owner's and Google's, drops the rest", () => {
    expect(trustedProfilePhoto(ownUrl("u1", "a.jpg"), "u1")).toBe(ownUrl("u1", "a.jpg"));
    expect(trustedProfilePhoto(ownUrl("u1", "a.jpg"), "u2")).toBeNull();
    expect(trustedProfilePhoto(evil, "u1")).toBeNull();
    expect(trustedProfilePhoto(42, "u1")).toBeNull();
  });

  it("a post gets no photo when Auth's and the profile's pictures are both evil", async () => {
    const s = setup();
    s.users.records.set("me", { name: "Mia", email: "m@x.test" }); // the lookup already dropped an evil Auth photo
    s.store.put("profiles/me", { name: "Mia", photoUrl: evil });
    const res = await s.call("POST", "/v1/posts", { body: "hello" });
    expect(res.statusCode).toBe(201);
    const post = [...s.store.docs.entries()].find(([k]) => /^posts\/[^/]+$/.test(k))![1];
    expect(post.authorPhotoUrl ?? null).toBeNull();
  });

  it("a post still shows the author's own picture from the profile", async () => {
    const s = setup();
    s.users.records.set("me", { name: "Mia" });
    s.store.put("profiles/me", { name: "Mia", photoUrl: ownUrl("me", "a.jpg") });
    const res = await s.call("POST", "/v1/posts", { body: "hello" });
    expect(res.statusCode).toBe(201);
    const post = [...s.store.docs.entries()].find(([k]) => /^posts\/[^/]+$/.test(k))![1];
    expect(post.authorPhotoUrl).toBe(ownUrl("me", "a.jpg"));
  });

  it("a follow drops an evil profile picture of the target", async () => {
    const s = setup();
    s.store.put("profiles/pat", { name: "Pat", photoUrl: evil });
    const res = await s.call("PUT", "/v1/follows", { type: "user", targetId: "pat" });
    expect(res.statusCode).toBe(200);
    expect(s.store.doc("users/me/follows/user_pat")?.photoUrl ?? null).toBeNull();
  });

  it("a block card drops an evil profile picture", async () => {
    const s = setup();
    s.store.put("profiles/pat", { name: "Pat", photoUrl: evil });
    const res = await s.call("PUT", "/v1/me/blocks/pat");
    expect(res.statusCode).toBeLessThan(300);
    expect(s.store.doc("users/me/blocks/pat")?.photoUrl ?? null).toBeNull();
  });
});

describe("N3: ACCOUNT_GATE_MODE when deployed", () => {
  const deployed = { NODE_ENV: "production", FIREBASE_PROJECT_ID: DEV_PROJECT_ID, PERSONAL_DETAILS_KMS_KEY: "projects/p/locations/l/keyRings/r/cryptoKeys/k" };
  it("is required: unset or blank fails startup", () => {
    expect(() => assertStartupEnvironment(deployed)).toThrow(/ACCOUNT_GATE_MODE must be set/);
    expect(() => assertStartupEnvironment({ ...deployed, ACCOUNT_GATE_MODE: "  " })).toThrow(StartupConfigError);
    expect(() => assertStartupEnvironment({ ...deployed, K_SERVICE: "api", NODE_ENV: "" })).toThrow(/ACCOUNT_GATE_MODE must be set/);
  });
  it("either explicit value boots", () => {
    expect(assertStartupEnvironment({ ...deployed, ACCOUNT_GATE_MODE: "enforce" })).toBe(DEV_PROJECT_ID);
    expect(assertStartupEnvironment({ ...deployed, ACCOUNT_GATE_MODE: "report" })).toBe(DEV_PROJECT_ID);
  });
  it("local and emulator runs keep the report default", () => {
    expect(accountGateModeFromEnv({})).toBe("report");
    // K_SERVICE with an emulator is refused outright now (review 3.1); a production build run against emulators keeps the waiver.
    expect(accountGateModeFromEnv({ NODE_ENV: "production", FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080" })).toBe("report");
  });
});

describe("N4: lifting a suspension and an under-13 account", () => {
  function setup() {
    const store = new FakeStore(() => now);
    const users = new FakeUsers();
    const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, personal: new FakeCipher(), now: () => now });
    const call = (method: "POST" | "PUT", url: string, body?: object, uid = "me", kind = "token") =>
      app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer ${kind}:${uid}` } });
    return { store, users, call };
  }
  const adult = { legalFirstName: "P", legalLastName: "L", birthDate: "", phone: "+1 555 010 2030", gender: "woman", address: { line1: "1 Main St", city: "Boston", region: "MA", postalCode: "02110" } };

  async function suspendThenLift(s: ReturnType<typeof setup>, birthDate: string) {
    s.users.records.set("pat", { name: "Pat" });
    await s.call("PUT", "/v1/me/personal", { ...adult, birthDate }, "pat"); // refused, remembered
    s.store.put("profiles/pat", { name: "Pat" });
    s.store.put("posts/p1", { authorId: "pat", authorName: "Pat", kind: "text", body: "x" });
    await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "p1" }, reason: "spam" }, "me");
    const id = reportId("me", { kind: "post", postId: "p1" });
    const staff = (action: string) => s.call("POST", `/v1/staff/reports/${id}`, { action }, "boss", "staff");
    expect((await staff("suspend")).statusCode).toBe(204);
    expect((await staff("unsuspend")).statusCode).toBe(204);
  }

  it("an under-13 account stays disabled after a suspension is lifted", async () => {
    const s = setup();
    await suspendThenLift(s, "2018-01-01");
    expect(s.store.doc("limits/pat")).toMatchObject({ suspended: false });
    expect(s.users.disabled.has("pat")).toBe(true);
  });

  it("a 13-17 refusal was never disabled, so lifting re-enables as before", async () => {
    const s = setup();
    await suspendThenLift(s, "2010-01-01");
    expect(s.users.disabled.has("pat")).toBe(false);
  });

  it("an account with no refusal is re-enabled", async () => {
    const s = setup();
    s.users.records.set("pat", { name: "Pat" });
    s.store.put("profiles/pat", { name: "Pat" });
    s.store.put("posts/p1", { authorId: "pat", authorName: "Pat", kind: "text", body: "x" });
    await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "p1" }, reason: "spam" }, "me");
    const id = reportId("me", { kind: "post", postId: "p1" });
    await s.call("POST", `/v1/staff/reports/${id}`, { action: "suspend" }, "boss", "staff");
    expect(s.users.disabled.has("pat")).toBe(true);
    await s.call("POST", `/v1/staff/reports/${id}`, { action: "unsuspend" }, "boss", "staff");
    expect(s.users.disabled.has("pat")).toBe(false);
  });
});

describe("review 4.1: lifting a suspension fails closed", () => {
  class ThrowingCipher extends FakeCipher {
    broken = false;
    override async open(...args: Parameters<FakeCipher["open"]>) {
      if (this.broken) throw new Error("kms unavailable");
      return super.open(...args);
    }
  }
  function setup(cipher?: PersonalCipher, users: FakeUsers = new FakeUsers()) {
    const store = new FakeStore(() => now);
    const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, ...(cipher && { personal: cipher }), now: () => now });
    const call = (method: "POST" | "PUT", url: string, body?: object, uid = "me", kind = "token") =>
      app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer ${kind}:${uid}` } });
    return { store, users, call };
  }
  const details = { legalFirstName: "P", legalLastName: "L", birthDate: "", phone: "+1 555 010 2030", gender: "woman", address: { line1: "1 Main St", city: "Boston", region: "MA", postalCode: "02110" } };

  /** Reports and suspends pat; returns a function that lifts it. */
  async function suspended(s: ReturnType<typeof setup>) {
    s.users.records.set("pat", { name: "Pat" });
    s.store.put("profiles/pat", { name: "Pat" });
    s.store.put("posts/p1", { authorId: "pat", authorName: "Pat", kind: "text", body: "x" });
    await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "p1" }, reason: "spam" }, "me");
    const id = reportId("me", { kind: "post", postId: "p1" });
    const staff = (action: string) => s.call("POST", `/v1/staff/reports/${id}`, { action }, "boss", "staff");
    expect((await staff("suspend")).statusCode).toBe(204);
    return () => staff("unsuspend");
  }

  it("a throwing cipher on lift (under-13 refusal) leaves Auth disabled and limits unchanged", async () => {
    const cipher = new ThrowingCipher();
    const s = setup(cipher);
    await s.call("PUT", "/v1/me/personal", { ...details, birthDate: "2018-01-01" }, "pat"); // refused, Auth disabled
    const lift = await suspended(s);
    const before = { ...s.store.doc("limits/pat") };
    cipher.broken = true;
    const res = await lift();
    expect(res.statusCode).toBeGreaterThanOrEqual(500);
    expect(s.users.disabled.has("pat")).toBe(true);
    expect(s.store.doc("limits/pat")).toEqual(before);
    expect(s.store.doc("limits/pat")).toMatchObject({ suspended: true });
  });

  it("with no cipher, any refusal record keeps the account disabled on lift", async () => {
    const s = setup();
    s.store.put("ageRefusals/pat", { ciphertext: "x", key: "k", format: 1, refusedAt: new Date(now) });
    const lift = await suspended(s);
    expect((await lift()).statusCode).toBe(204);
    expect(s.users.disabled.has("pat")).toBe(true);
  });

  it("an under-18-only refusal is re-enabled on lift", async () => {
    const s = setup(new FakeCipher());
    await s.call("PUT", "/v1/me/personal", { ...details, birthDate: "2010-01-01" }, "pat");
    const lift = await suspended(s);
    expect((await lift()).statusCode).toBe(204);
    expect(s.users.disabled.has("pat")).toBe(false);
    expect(s.store.doc("limits/pat")).toMatchObject({ suspended: false });
  });

  it("a refusal whose date can't be read keeps the account disabled (3a-F: fails closed)", async () => {
    const cipher = new FakeCipher();
    const s = setup(cipher);
    const sealed = await cipher.seal(Buffer.from("{}", "utf8"), "ageRefusals/pat");
    s.store.put("ageRefusals/pat", { ciphertext: sealed.ciphertext, key: sealed.key, format: 1, refusedAt: new Date(now) });
    const lift = await suspended(s);
    expect((await lift()).statusCode).toBe(204);
    expect(s.users.disabled.has("pat")).toBe(true);
  });

  it("an under-13 refusal that lands while the lift runs disables the account again (4.1b race)", async () => {
    const cipher = new FakeCipher();
    let arrive: () => Promise<void> = async () => {};
    class RacyUsers extends FakeUsers {
      override async setDisabled(uid: string, disabled: boolean) {
        await super.setDisabled(uid, disabled);
        if (!disabled) await arrive();
      }
    }
    const s = setup(cipher, new RacyUsers());
    const lift = await suspended(s);
    arrive = async () => {
      // The refusal arrives between the check and the re-enable.
      const sealed = await cipher.seal(Buffer.from(JSON.stringify({ birthDate: "2018-01-01" }), "utf8"), "ageRefusals/pat");
      s.store.put("ageRefusals/pat", { ciphertext: sealed.ciphertext, key: sealed.key, format: 1, refusedAt: new Date(now) });
    };
    expect((await lift()).statusCode).toBe(204);
    expect(s.users.disabled.has("pat")).toBe(true);
  });

  it("if the second age check throws, the account is disabled again and the error surfaces (L5)", async () => {
    let arrive: () => void = () => {};
    class RacyUsers extends FakeUsers {
      override async setDisabled(uid: string, disabled: boolean) {
        await super.setDisabled(uid, disabled);
        if (!disabled) arrive();
      }
    }
    const s = setup(new FakeCipher(), new RacyUsers());
    const lift = await suspended(s);
    arrive = () => {
      const get = s.store.get.bind(s.store);
      s.store.get = async (path: string) => {
        if (path === "ageRefusals/pat") throw new Error("store down");
        return get(path);
      };
    };
    expect((await lift()).statusCode).toBe(500);
    expect(s.users.disabled.has("pat")).toBe(true);
  });

  it("an under-13 refusal whose refusedAt isn't a Date keeps the account disabled", async () => {
    const s = setup(new FakeCipher());
    await s.call("PUT", "/v1/me/personal", { ...details, birthDate: "2018-01-01" }, "pat");
    s.store.put("ageRefusals/pat", { ...s.store.doc("ageRefusals/pat")!, refusedAt: "not-a-date" });
    const lift = await suspended(s);
    expect((await lift()).statusCode).toBe(204);
    expect(s.users.disabled.has("pat")).toBe(true);
  });
});

describe("review 3.1: no emulator variable on Cloud Run", () => {
  const cloud = { K_SERVICE: "api", FIREBASE_PROJECT_ID: DEV_PROJECT_ID, PERSONAL_DETAILS_KMS_KEY: "projects/p/locations/l/keyRings/r/cryptoKeys/k", ACCOUNT_GATE_MODE: "report" };
  it("boots with none", () => expect(assertStartupEnvironment(cloud)).toBe(DEV_PROJECT_ID));
  it.each(["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"])("K_SERVICE with %s throws, naming the variable but not its value", (name) => {
    const env = { ...cloud, [name]: "secret-host:1234" };
    expect(() => assertStartupEnvironment(env)).toThrow(StartupConfigError);
    expect(() => assertStartupEnvironment(env)).toThrow(new RegExp(name));
    expect(() => assertStartupEnvironment(env)).not.toThrow(/secret-host/);
    expect(() => accountGateModeFromEnv(env)).toThrow(StartupConfigError);
  });
  it("K_SERVICE with no ACCOUNT_GATE_MODE throws", () => {
    const { ACCOUNT_GATE_MODE: _omit, ...env } = cloud;
    expect(() => assertStartupEnvironment(env)).toThrow(/ACCOUNT_GATE_MODE must be set/);
  });
});
