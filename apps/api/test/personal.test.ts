// Personal details through the API (packages/shared/src/personal.ts):
// encrypted at rest, only ever the caller's own, under 13 refused.
import { tooYoungMessage } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { LocalCipher } from "../src/personal/cipher.js";
import { FakeCipher, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12); // 20 Nov 2026
const D = "personalDetails/u1";

const adult = {
  legalFirstName: " Patricia ",
  legalLastName: "Lee",
  birthDate: "1995-04-02",
  phone: "+1 (555) 010-2030",
  gender: "woman",
  address: { line1: "1 Main St", city: "Boston", region: "MA", postalCode: "02110" },
};
const guardian = { name: "Sam Lee", relationship: "Parent", email: "sam@x.test", phone: "555-010-9999" };

function setup(withCipher = true) {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const cipher = new FakeCipher();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users,
    teams: new FakeTeamRepository(),
    store,
    personal: withCipher ? cipher : undefined,
    now: () => now,
  });
  const call = (method: "GET" | "PUT", url: string, body?: object, uid = "u1") =>
    app.inject({ method, url, payload: body, headers: { authorization: `Bearer token:${uid}` } });
  return { store, users, cipher, app, call };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.users.records.set("u1", { name: "Pat", email: "pat@x.test", createdAt: "2026-11-15T09:00:00.000Z" });
});

describe("PUT /v1/me/personal", () => {
  it("stores only ciphertext, bound to the document", async () => {
    const res = await s.call("PUT", "/v1/me/personal", adult);
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toBe("private, no-store");
    const doc = s.store.doc(D)!;
    expect(Object.keys(doc).sort()).toEqual(["ciphertext", "format", "key", "updatedAt"]);
    expect(doc.key).toBe("fake-key");
    expect(JSON.stringify(doc)).not.toMatch(/Patricia|1995|Boston|555/);
  });

  it("reads back what was saved, trimmed, with defaults", async () => {
    await s.call("PUT", "/v1/me/personal", adult);
    const res = await s.call("GET", "/v1/me/personal");
    expect(res.headers["cache-control"]).toBe("private, no-store");
    expect(res.json()).toEqual({
      email: "pat@x.test",
      details: {
        ...adult,
        legalFirstName: "Patricia",
        address: { ...adult.address, line2: "", country: "US" },
      },
    });
  });

  it("refuses under 13 and saves nothing", async () => {
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2014-01-01", guardian });
    expect(res.statusCode).toBe(412);
    expect(res.json().error).toEqual({
      code: "failed_precondition",
      message: tooYoungMessage,
      fields: { birthDate: tooYoungMessage },
    });
    expect(s.store.doc(D)).toBeUndefined();
    expect(s.cipher.calls.seal).toBe(0);
  });

  it("counts birthdays in the furthest-ahead time zone (UTC+14)", async () => {
    // 20 Nov 12:00 UTC is already 21 Nov in Kiribati.
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2013-11-21", guardian });
    expect(res.statusCode).toBe(200);
    expect((await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2013-11-22", guardian })).statusCode).toBe(412);
  });

  it("allows a 13th birthday today", async () => {
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2013-11-20", guardian });
    expect(res.statusCode).toBe(200);
  });

  it("needs a guardian under 18", async () => {
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2010-01-01" });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.fields).toHaveProperty("guardian");
  });

  it("keeps a minor's guardian, drops an adult's", async () => {
    await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2010-01-01", guardian });
    expect((await s.call("GET", "/v1/me/personal")).json().details.guardian).toEqual(guardian);
    await s.call("PUT", "/v1/me/personal", { ...adult, guardian });
    expect((await s.call("GET", "/v1/me/personal")).json().details).not.toHaveProperty("guardian");
  });

  it.each([
    ["a bad date", { birthDate: "1995-02-30" }, "birthDate"],
    ["a future date", { birthDate: "2027-01-01" }, "birthDate"],
    ["a bad phone", { phone: "call me" }, "phone"],
    ["an unknown gender", { gender: "x" }, "gender"],
    ["a missing city", { address: { ...adult.address, city: " " } }, "address.city"],
    ["extra fields", { ssn: "123" }, "_"],
  ])("refuses %s", async (_, change, field) => {
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, ...change });
    expect(res.statusCode).toBe(400);
    expect(Object.keys(res.json().error.fields ?? { _: 1 })).toContain(field);
    expect(s.store.doc(D)).toBeUndefined();
  });

  it("never echoes what was sent in an error", async () => {
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, phone: "secret-555" });
    expect(res.body).not.toContain("secret-555");
  });
});

describe("only the caller's own", () => {
  it("another user gets their own (empty) record", async () => {
    await s.call("PUT", "/v1/me/personal", adult);
    const res = await s.call("GET", "/v1/me/personal", undefined, "u2");
    expect(res.json()).toEqual({ details: null, email: "u2@x.test" });
  });

  it("a record copied to another user's path doesn't open", async () => {
    await s.call("PUT", "/v1/me/personal", adult);
    s.store.put("personalDetails/u2", s.store.doc(D)!);
    expect((await s.call("GET", "/v1/me/personal", undefined, "u2")).statusCode).toBe(500);
  });

  it("needs signing in", async () => {
    const res = await s.app.inject({ method: "GET", url: "/v1/me/personal" });
    expect(res.statusCode).toBe(401);
  });
});

describe("GET /v1/me/personal/status", () => {
  it("required for accounts made since the cutoff, without decrypting", async () => {
    expect((await s.call("GET", "/v1/me/personal/status")).json()).toEqual({ complete: false, required: true });
    await s.call("PUT", "/v1/me/personal", adult);
    expect((await s.call("GET", "/v1/me/personal/status")).json()).toEqual({ complete: true, required: true });
    expect(s.cipher.calls.open).toBe(0);
  });

  it("not required for older accounts, or when the creation time is unknown", async () => {
    s.users.records.set("u1", { createdAt: "2025-06-01T00:00:00.000Z" });
    expect((await s.call("GET", "/v1/me/personal/status")).json().required).toBe(false);
    s.users.records.set("u1", {});
    expect((await s.call("GET", "/v1/me/personal/status")).json().required).toBe(false);
  });
});

it("is off without a cipher (never stored in the clear)", async () => {
  const off = setup(false);
  expect((await off.call("PUT", "/v1/me/personal", adult)).statusCode).toBe(404);
});

describe("LocalCipher (emulators)", () => {
  const c = new LocalCipher(Buffer.alloc(32, 7).toString("base64"));
  it("round-trips and checks the context", async () => {
    const sealed = await c.seal(Buffer.from("hello"), "personalDetails/u1");
    expect((await c.open(sealed, "personalDetails/u1")).toString()).toBe("hello");
    await expect(c.open(sealed, "personalDetails/u2")).rejects.toThrow();
  });
  it("refuses a short key", () => {
    expect(() => new LocalCipher("c2hvcnQ=")).toThrow();
  });
});
