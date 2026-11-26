// Personal details through the API (packages/shared/src/personal.ts):
// encrypted at rest, only ever the caller's own, under 13 refused, under 18
// refused (adults-only launch), the birth date locked once saved.
import { adultOnlyMessage, birthDateLockedMessage, tooYoungMessage } from "@stall10/shared";
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
    // Only the sealed refusal is kept (F3), never anything readable.
    expect(Object.keys(s.store.doc("ageRefusals/u1")!).sort()).toEqual(["ciphertext", "format", "key", "refusedAt"]);
  });

  it("counts 18th birthdays in the furthest-ahead time zone (UTC+14)", async () => {
    // 20 Nov 12:00 UTC is already 21 Nov in Kiribati.
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2008-11-21" });
    expect(res.statusCode).toBe(200);
    s.store.docs.delete(D);
    const tooYoungForNow = await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2008-11-22" });
    expect(tooYoungForNow.statusCode).toBe(412);
    expect(s.store.doc(D)).toBeUndefined();
  });

  it("allows an 18th birthday today", async () => {
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2008-11-20" });
    expect(res.statusCode).toBe(200);
  });

  it.each([
    ["13", "2013-11-20"],
    ["16", "2010-01-01"],
    ["17", "2009-06-01"],
  ])("refuses a %s-year-old (adults only), with or without a guardian, and saves nothing", async (_, birthDate) => {
    for (const body of [{ ...adult, birthDate }, { ...adult, birthDate, guardian }]) {
      const res = await s.call("PUT", "/v1/me/personal", body);
      expect(res.statusCode).toBe(412);
      expect(res.json().error).toEqual({
        code: "failed_precondition",
        message: adultOnlyMessage,
        fields: { birthDate: adultOnlyMessage },
      });
    }
    expect(s.store.doc(D)).toBeUndefined();
    // Only the sealed refusal is kept (F3), never anything readable.
    expect(Object.keys(s.store.doc("ageRefusals/u1")!).sort()).toEqual(["ciphertext", "format", "key", "refusedAt"]);
  });

  it("never keeps a guardian (everyone is an adult)", async () => {
    await s.call("PUT", "/v1/me/personal", { ...adult, guardian });
    expect((await s.call("GET", "/v1/me/personal")).json().details).not.toHaveProperty("guardian");
  });

  it("locks the birth date once saved: another one is refused and changes nothing", async () => {
    await s.call("PUT", "/v1/me/personal", adult);
    const before = s.store.doc(D);
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "1990-01-01" });
    expect(res.statusCode).toBe(412);
    expect(res.json().error).toEqual({
      code: "failed_precondition",
      message: birthDateLockedMessage,
      fields: { birthDate: birthDateLockedMessage },
    });
    expect(s.store.doc(D)).toEqual(before);
    expect((await s.call("GET", "/v1/me/personal")).json().details.birthDate).toBe("1995-04-02");
  });

  it("still lets the rest of the details change, with the same birth date", async () => {
    await s.call("PUT", "/v1/me/personal", adult);
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, phone: "+1 555 010 4444" });
    expect(res.statusCode).toBe(200);
    expect((await s.call("GET", "/v1/me/personal")).json().details.phone).toBe("+1 555 010 4444");
  });

  it("locks a birth date saved at sign-up too, against the full form", async () => {
    await s.call("PUT", "/v1/me/personal/birth-date", { birthDate: "1996-01-01" });
    const res = await s.call("PUT", "/v1/me/personal", adult);
    expect(res.statusCode).toBe(412);
    expect(res.json().error.fields.birthDate).toBe(birthDateLockedMessage);
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

describe("PUT /v1/me/personal/birth-date (sign-up)", () => {
  const B = "/v1/me/personal/birth-date";

  it("stores only ciphertext, sealed like the details, bound to the document", async () => {
    const res = await s.call("PUT", B, { birthDate: "1995-04-02" });
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toBe("private, no-store");
    const doc = s.store.doc(D)!;
    expect(Object.keys(doc).sort()).toEqual(["birthDateOnly", "ciphertext", "format", "key", "updatedAt"]);
    expect(doc.key).toBe("fake-key");
    expect(JSON.stringify(doc)).not.toMatch(/1995/);
    // The record a birthday-on-file check opens: the same ciphertext slot
    // and context as the full details, with a birthDate inside.
    const plain = await s.cipher.open({ ciphertext: String(doc.ciphertext), key: String(doc.key) }, D);
    expect(JSON.parse(plain.toString())).toEqual({ birthDate: "1995-04-02" });
  });

  it("comes back to its owner for About you, without completing the details", async () => {
    await s.call("PUT", B, { birthDate: "1995-04-02" });
    expect((await s.call("GET", "/v1/me/personal")).json()).toEqual({
      details: null,
      email: "pat@x.test",
      signUpBirthDate: "1995-04-02",
    });
    expect((await s.call("GET", "/v1/me/personal/status")).json()).toEqual({ complete: false, required: true });
  });

  it("is only ever the caller's own", async () => {
    await s.call("PUT", B, { birthDate: "1995-04-02" });
    expect((await s.call("GET", "/v1/me/personal", undefined, "u2")).json()).toEqual({ details: null, email: "u2@x.test" });
    expect(s.store.doc("personalDetails/u2")).toBeUndefined();
    expect((await s.app.inject({ method: "PUT", url: B, payload: { birthDate: "1995-04-02" } })).statusCode).toBe(401);
  });

  it("is replaced whole by the full details, which complete them", async () => {
    await s.call("PUT", B, { birthDate: "1995-04-02" });
    await s.call("PUT", "/v1/me/personal", adult);
    expect(s.store.doc(D)).not.toHaveProperty("birthDateOnly");
    const got = (await s.call("GET", "/v1/me/personal")).json();
    expect(got.details.birthDate).toBe("1995-04-02");
    expect(got).not.toHaveProperty("signUpBirthDate");
    expect((await s.call("GET", "/v1/me/personal/status")).json().complete).toBe(true);
  });

  it("can't change saved details", async () => {
    await s.call("PUT", "/v1/me/personal", adult);
    const before = s.store.doc(D);
    const res = await s.call("PUT", B, { birthDate: "2000-01-01" });
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe("already_exists");
    expect(s.store.doc(D)).toEqual(before);
    expect((await s.call("GET", "/v1/me/personal")).json().details.birthDate).toBe("1995-04-02");
  });

  it("can be given again until then, but only the same date (the birth date is locked once saved)", async () => {
    await s.call("PUT", B, { birthDate: "1995-04-02" });
    const changed = await s.call("PUT", B, { birthDate: "1995-04-03" });
    expect(changed.statusCode).toBe(412);
    expect(changed.json().error.fields.birthDate).toBe(birthDateLockedMessage);
    expect((await s.call("GET", "/v1/me/personal")).json().signUpBirthDate).toBe("1995-04-02");
    expect((await s.call("PUT", B, { birthDate: "1995-04-02" })).statusCode).toBe(200);
  });

  it("refuses under 13 with the under-13 message, and saves nothing", async () => {
    const res = await s.call("PUT", B, { birthDate: "2013-11-22" });
    expect(res.statusCode).toBe(412);
    expect(res.json().error).toEqual({
      code: "failed_precondition",
      message: tooYoungMessage,
      fields: { birthDate: tooYoungMessage },
    });
    expect(s.store.doc(D)).toBeUndefined();
    // Only the sealed refusal is kept (F3), never anything readable.
    expect(Object.keys(s.store.doc("ageRefusals/u1")!).sort()).toEqual(["ciphertext", "format", "key", "refusedAt"]);
  });

  it.each(["2008-11-22", "2010-01-01", "2013-11-21"])("refuses %s (under 18, adults only) and saves nothing", async (birthDate) => {
    const res = await s.call("PUT", B, { birthDate });
    expect(res.statusCode).toBe(412);
    expect(res.json().error).toEqual({
      code: "failed_precondition",
      message: adultOnlyMessage,
      fields: { birthDate: adultOnlyMessage },
    });
    expect(s.store.doc(D)).toBeUndefined();
    // Only the sealed refusal is kept (F3), never anything readable.
    expect(Object.keys(s.store.doc("ageRefusals/u1")!).sort()).toEqual(["ciphertext", "format", "key", "refusedAt"]);
  });

  it("allows an 18th birthday today in UTC+14", async () => {
    expect((await s.call("PUT", B, { birthDate: "2008-11-21" })).statusCode).toBe(200);
  });

  it.each([
    ["a bad date", { birthDate: "1995-02-30" }],
    ["a future date", { birthDate: "2027-01-01" }],
    ["no date", {}],
    ["extra fields", { birthDate: "1995-04-02", phone: "555" }],
  ])("refuses %s", async (_, body) => {
    const res = await s.call("PUT", B, body);
    expect(res.statusCode).toBe(400);
    expect(s.store.doc(D)).toBeUndefined();
    expect(res.body).not.toContain("1995");
  });

  it("is rate limited", async () => {
    for (let i = 0; i < 5; i++) expect((await s.call("PUT", B, { birthDate: "1995-04-02" })).statusCode).toBe(200);
    expect((await s.call("PUT", B, { birthDate: "1995-04-02" })).statusCode).toBe(429);
    // Someone else's own count.
    expect((await s.call("PUT", B, { birthDate: "1995-04-02" }, "u2")).statusCode).toBe(200);
  });

  it("is off without a cipher", async () => {
    const off = setup(false);
    expect((await off.call("PUT", B, { birthDate: "1995-04-02" })).statusCode).toBe(404);
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

describe("a refused birth date is remembered (F3)", () => {
  const B = "/v1/me/personal/birth-date";

  it("a refused 17-year-old can't then save an adult date, on either route", async () => {
    expect((await s.call("PUT", B, { birthDate: "2009-06-01" })).statusCode).toBe(412);
    for (const res of [await s.call("PUT", B, { birthDate: "1995-04-02" }), await s.call("PUT", "/v1/me/personal", adult)]) {
      expect(res.statusCode).toBe(412);
      expect(res.json().error.message).toBe(birthDateLockedMessage);
    }
    expect(s.store.doc(D)).toBeUndefined();
    expect(s.users.claims.size).toBe(0);
  });

  it("the full form's refusal is remembered against the sign-up form too", async () => {
    await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2009-06-01" });
    expect((await s.call("PUT", B, { birthDate: "1995-04-02" })).json().error.message).toBe(birthDateLockedMessage);
  });

  it("the same refused date again is refused the same way and changes nothing", async () => {
    await s.call("PUT", B, { birthDate: "2009-06-01" });
    const kept = JSON.stringify(s.store.doc("ageRefusals/u1"));
    const again = await s.call("PUT", B, { birthDate: "2009-06-01" });
    expect(again.statusCode).toBe(412);
    expect(again.json().error.message).toBe(adultOnlyMessage);
    expect(JSON.stringify(s.store.doc("ageRefusals/u1"))).toBe(kept);
  });

  it("keeps the refusal sealed and bound to the account, never readable", async () => {
    await s.call("PUT", B, { birthDate: "2009-06-01" });
    const doc = s.store.doc("ageRefusals/u1")!;
    expect(Object.keys(doc).sort()).toEqual(["ciphertext", "format", "key", "refusedAt"]);
    expect(JSON.stringify(doc)).not.toContain("2009");
    // Copied to another user's path it doesn't open (the path is the cipher's context).
    s.store.put("ageRefusals/u2", doc);
    expect((await s.call("PUT", B, { birthDate: "1995-04-02" }, "u2")).statusCode).toBe(500);
  });

  it("one user's refusal doesn't touch another's", async () => {
    await s.call("PUT", B, { birthDate: "2009-06-01" });
    s.users.records.set("u2", { name: "Sam", createdAt: "2026-11-15T09:00:00.000Z" });
    expect((await s.call("PUT", B, { birthDate: "1995-04-02" }, "u2")).statusCode).toBe(200);
  });

  it("an under-13 attempt disables the Auth account; under 18 does not", async () => {
    await s.call("PUT", B, { birthDate: "2009-06-01" });
    expect(s.users.disabled.has("u1")).toBe(false);
    s.users.records.set("u2", { name: "Kit", createdAt: "2026-11-15T09:00:00.000Z" });
    const res = await s.call("PUT", B, { birthDate: "2015-01-01" }, "u2");
    expect(res.json().error.message).toBe(tooYoungMessage);
    expect(s.users.disabled.has("u2")).toBe(true);
  });

  it("an under-13 attempt through the full form disables the account too", async () => {
    await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2015-01-01" });
    expect(s.users.disabled.has("u1")).toBe(true);
  });

  it("an adult with a saved date can't be disabled by trying a child's date", async () => {
    await s.call("PUT", "/v1/me/personal", adult);
    const res = await s.call("PUT", "/v1/me/personal", { ...adult, birthDate: "2015-01-01" });
    expect(res.json().error.message).toBe(birthDateLockedMessage);
    expect(s.users.disabled.size).toBe(0);
    expect(s.store.doc("ageRefusals/u1")).toBeUndefined();
  });

  it("a refused 17-year-old trying an under-13 date is locked, not disabled", async () => {
    await s.call("PUT", B, { birthDate: "2009-06-01" });
    const res = await s.call("PUT", B, { birthDate: "2015-01-01" });
    expect(res.json().error.message).toBe(birthDateLockedMessage);
    expect(s.users.disabled.size).toBe(0);
  });

  it("there is no override: a staff token can't clear it", async () => {
    await s.call("PUT", B, { birthDate: "2009-06-01" });
    const res = await s.app.inject({ method: "PUT", url: B, payload: { birthDate: "1995-04-02" }, headers: { authorization: "Bearer staff:u1" } });
    expect(res.statusCode).toBe(412);
  });
});

describe("PUT /v1/me/personal is rate limited (F3)", () => {
  it("5 a minute per account, then 429; another account is unaffected", async () => {
    const codes: number[] = [];
    for (let i = 0; i < 6; i++) codes.push((await s.call("PUT", "/v1/me/personal", adult)).statusCode);
    expect(codes.slice(0, 5)).toEqual([200, 200, 200, 200, 200]);
    expect(codes[5]).toBe(429);
    s.users.records.set("u2", { name: "Sam", createdAt: "2026-11-15T09:00:00.000Z" });
    expect((await s.call("PUT", "/v1/me/personal", adult, "u2")).statusCode).toBe(200);
  });
});

describe("GET /v1/me/personal/status is rate limited (F4)", () => {
  it("10 a minute per account, then 429", async () => {
    const codes: number[] = [];
    for (let i = 0; i < 11; i++) codes.push((await s.call("GET", "/v1/me/personal/status")).statusCode);
    expect(codes.slice(0, 10).every((c) => c === 200)).toBe(true);
    expect(codes[10]).toBe(429);
    expect((await s.call("GET", "/v1/me/personal/status", undefined, "u2")).statusCode).toBe(200);
  });
});
