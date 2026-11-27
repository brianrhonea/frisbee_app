// The account gate (docs/specifications/contracts/account-gate.md, SEC-2):
// writes need a verified email, the `ageOk` claim (a saved birth date of 18+)
// and the `terms` claim; reads and the onboarding routes don't. The claims
// are set by the API from stored records, including for accounts that
// existed before the gate (the status endpoint).
import { accountGateMessages, adultOnlyMessage, termsVersion } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeCipher, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12);
const adult = {
  legalFirstName: "Pat",
  legalLastName: "Lee",
  birthDate: "1995-04-02",
  phone: "+1 (555) 010-2030",
  gender: "woman",
  address: { line1: "1 Main St", city: "Boston", region: "MA", postalCode: "02110" },
};

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const cipher = new FakeCipher();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users,
    teams: new FakeTeamRepository(),
    store,
    personal: cipher,
    now: () => now,
    writeLimits: false,
  });
  const call = (kind: string, method: "GET" | "PUT" | "POST" | "PATCH" | "DELETE", url: string, body?: object, uid = "u1") =>
    app.inject({ method, url, payload: body, headers: { authorization: `Bearer ${kind}:${uid}` } });
  return { store, users, cipher, app, call };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.users.records.set("u1", { name: "Pat", email: "u1@x.test", createdAt: "2026-11-15T09:00:00.000Z" });
});

/** A spread of writes across every area the rules cover; the gate answers before any body is read. */
const writes: Array<[string, "PUT" | "POST" | "PATCH" | "DELETE", string]> = [
  ["a post", "POST", "/v1/posts"],
  ["a comment", "POST", "/v1/posts/p1/comments"],
  ["a like", "PUT", "/v1/posts/p1/like"],
  ["a follow", "PUT", "/v1/follows"],
  ["a team", "POST", "/v1/teams"],
  ["a join by code", "POST", "/v1/teams/join"],
  ["a join request", "POST", "/v1/teams/t1/join-requests"],
  ["a team post", "POST", "/v1/teams/t1/posts"],
  ["a chat message", "POST", "/v1/teams/t1/chats/r1/messages"],
  ["an RSVP", "PUT", "/v1/teams/t1/events/e1/rsvp"],
  ["a conversation", "POST", "/v1/conversations"],
  ["a direct message", "POST", "/v1/conversations/c1/messages"],
  ["a report", "POST", "/v1/reports"],
  ["a tournament", "POST", "/v1/tournaments"],
  ["a block", "PUT", "/v1/me/blocks/u2"],
  ["a calendar", "POST", "/v1/me/calendars"],
  ["a team deletion", "DELETE", "/v1/teams/t1"],
];

describe("writes by an incomplete account", () => {
  const cases: Array<[string, string, string[]]> = [
    ["unverified", "unverified", ["email_unverified"]],
    ["noage", "no ageOk claim", ["age"]],
    ["noterms", "no terms claim", ["terms"]],
    ["oldterms", "an older Terms version", ["terms"]],
    ["bare", "a REST-created account (no claims, no verified email)", ["email_unverified", "age", "terms"]],
  ];

  for (const [kind, label, missing] of cases) {
    it.each(writes)(`${label}: refuses %s with 403 account_incomplete`, async (_, method, url) => {
      const res = await s.call(kind, method, url, {});
      expect(res.statusCode).toBe(403);
      const e = res.json().error;
      expect(e.code).toBe("account_incomplete");
      expect(Object.keys(e.fields)).toEqual(missing);
      expect(e.message).toBe(accountGateMessages[missing[0] as keyof typeof accountGateMessages]);
    });
  }

  it("is refused before the body is read (nothing about the request is used)", async () => {
    const res = await s.call("bare", "POST", "/v1/posts", { not: "valid" });
    expect(res.statusCode).toBe(403);
  });

  it("reports the first missing requirement in the message, in the order email, age, terms", async () => {
    const res = await s.call("bare", "POST", "/v1/posts", {});
    expect(res.json().error.message).toBe(accountGateMessages.email_unverified);
  });

  it("changes nothing in the store", async () => {
    const before = [...s.store.docs.keys()];
    await s.call("bare", "POST", "/v1/posts", { text: "hello" });
    await s.call("noage", "PUT", "/v1/follows", {});
    expect([...s.store.docs.keys()]).toEqual(before);
  });
});

describe("a complete account", () => {
  it.each(writes)("passes the gate for %s (a bad body is a 400, a missing thing a 4xx, never a 403 account_incomplete)", async (_, method, url) => {
    const res = await s.call("token", method, url, {});
    expect(res.json()?.error?.code).not.toBe("account_incomplete");
  });
});

describe("reads stay open", () => {
  it.each([
    ["GET", "/v1/me/personal"],
    ["GET", "/v1/me/agreement"],
    ["GET", "/v1/me/personal/status"],
    ["GET", "/v1/me/message-policy"],
  ] as const)("an account with nothing may %s %s", async (method, url) => {
    const res = await s.call("bare", method, url);
    expect(res.statusCode).toBe(200);
  });
});

describe("the onboarding routes stay open to an incomplete account", () => {
  it("personal details, sign-up birth date, agreement", async () => {
    expect((await s.call("bare", "PUT", "/v1/me/personal/birth-date", { birthDate: "1995-04-02" })).statusCode).toBe(200);
    expect((await s.call("bare", "PUT", "/v1/me/personal", adult)).statusCode).toBe(200);
    expect((await s.call("bare", "PUT", "/v1/me/agreement", { version: termsVersion })).statusCode).toBe(200);
  });

  it.each([
    ["PUT", "/v1/me/message-policy"],
    ["PUT", "/v1/me/read-receipts"],
    ["PUT", "/v1/me/notification-settings/category"],
    ["PUT", "/v1/me/notification-settings/mute"],
    ["DELETE", "/v1/me/notification-settings/teams/t1"],
  ] as const)("%s %s is not gated (a bad body may fail validation, never account_incomplete)", async (method, url) => {
    const res = await s.call("bare", method, url, {});
    expect(res.body).not.toContain("account_incomplete");
  });
});

/** Identity, username and profile writes build a searchable profile: they need the adult check (F1). */
const ageGated = [
  ["PUT", "/v1/me/identity"],
  ["POST", "/v1/me/username"],
  ["PUT", "/v1/me/profile/details"],
  ["PUT", "/v1/me/profile/privacy"],
  ["PUT", "/v1/me/profile/visibility"],
] as const;

describe("profile, username and identity writes need ageOk, and nothing else (F1)", () => {
  it.each(ageGated)("%s %s refuses an account with no age claim, naming only age", async (method, url) => {
    for (const kind of ["bare", "noage"]) {
      const res = await s.call(kind, method, url, {});
      expect(res.statusCode).toBe(403);
      expect(res.json().error.code).toBe("account_incomplete");
      expect(Object.keys(res.json().error.fields)).toEqual(["age"]);
    }
  });

  it.each(ageGated)("%s %s lets an adult through while the email or Terms are pending", async (method, url) => {
    for (const kind of ["unverified", "noterms", "oldterms"]) {
      const res = await s.call(kind, method, url, {});
      expect(res.body).not.toContain("account_incomplete");
    }
  });

  it("a refused minor never gets the claim, so never a profile", async () => {
    await s.call("bare", "PUT", "/v1/me/personal/birth-date", { birthDate: "2009-06-01" });
    expect(s.users.claims.size).toBe(0);
    const res = await s.call("bare", "PUT", "/v1/me/profile/details", {});
    expect(res.statusCode).toBe(403);
  });
});

describe("the claims", () => {
  it("saving an adult's birth date at sign-up sets ageOk and tells the client to refresh its token", async () => {
    const res = await s.call("bare", "PUT", "/v1/me/personal/birth-date", { birthDate: "1995-04-02" });
    expect(res.json()).toEqual({ refreshToken: true });
    expect(s.users.claims.get("u1")).toEqual({ ageOk: true });
  });

  it("saving the full details sets ageOk; agreeing sets terms; each says to refresh", async () => {
    expect((await s.call("noage", "PUT", "/v1/me/personal", adult)).json()).toEqual({ refreshToken: true });
    expect(s.users.claims.get("u1")).toEqual({ ageOk: true });
    const agreed = await s.call("noterms", "PUT", "/v1/me/agreement", { version: termsVersion });
    expect(agreed.json()).toEqual({ agreed: true, version: termsVersion, refreshToken: true });
    expect(s.users.claims.get("u1")).toEqual({ ageOk: true, terms: termsVersion });
  });

  it("D-1317: the profile gets adult:true wherever the age claim is issued or already held, never for a minor, and is never created", async () => {
    s.store.put("profiles/u1", { name: "Pat" });
    await s.call("bare", "PUT", "/v1/me/personal/birth-date", { birthDate: "1995-04-02" });
    expect(s.store.doc("profiles/u1")).toEqual({ name: "Pat", adult: true });
    // A caller whose token already says ageOk is marked by the next status call.
    s.store.put("profiles/u2", { name: "Una" });
    await s.call("token", "GET", "/v1/me/personal/status", undefined, "u2");
    expect(s.store.doc("profiles/u2")).toEqual({ name: "Una", adult: true });
    // A minor's profile is left alone; with no profile nothing is made.
    s.store.put("profiles/u3", { name: "Teen" });
    await s.call("bare", "PUT", "/v1/me/personal/birth-date", { birthDate: "2009-06-01" }, "u3");
    expect(s.store.doc("profiles/u3")).toEqual({ name: "Teen" });
    await s.call("token", "GET", "/v1/me/personal/status", undefined, "u4");
    expect(s.store.doc("profiles/u4")).toBeUndefined();
  });

  it("agreeing before a birth date sets only terms", async () => {
    await s.call("bare", "PUT", "/v1/me/agreement", { version: termsVersion });
    expect(s.users.claims.get("u1")).toEqual({ terms: termsVersion });
  });

  it("a token that already carries the claims isn't told to refresh", async () => {
    const res = await s.call("token", "PUT", "/v1/me/personal", adult);
    expect(res.json()).toEqual({});
    expect(s.users.claims.size).toBe(0);
  });

  it("an under-18 birth date is refused and sets no claim, nor leaves a readable record", async () => {
    const res = await s.call("bare", "PUT", "/v1/me/personal/birth-date", { birthDate: "2008-11-22" });
    expect(res.statusCode).toBe(412);
    expect(res.json().error.message).toBe(adultOnlyMessage);
    // A different date afterwards is refused as locked, not tried again (F3).
    const other = await s.call("bare", "PUT", "/v1/me/personal/birth-date", { birthDate: "1990-01-01" });
    expect(other.statusCode).toBe(412);
    expect(s.users.claims.size).toBe(0);
    expect(s.store.doc("personalDetails/u1")).toBeUndefined();
    // And so the account still can't write.
    expect((await s.call("bare", "POST", "/v1/posts", {})).statusCode).toBe(403);
  });

  it("a claim can't be had from the request: a body naming one changes nothing", async () => {
    const res = await s.call("bare", "PUT", "/v1/me/personal/birth-date", { birthDate: "1995-04-02", ageOk: true });
    expect(res.statusCode).toBe(400);
    expect(s.users.claims.size).toBe(0);
  });

  it("the birth date can't be changed to get past the gate, nor to change the age", async () => {
    await s.call("bare", "PUT", "/v1/me/personal", adult);
    const res = await s.call("token", "PUT", "/v1/me/personal", { ...adult, birthDate: "1980-01-01" });
    expect(res.statusCode).toBe(412);
  });
});

describe("existing accounts (lazy backfill through the status endpoint)", () => {
  /** An account made before the gate: details and agreement on file, no claims. */
  async function existing(birthDate: string, agreed = true) {
    s.store.put("users/u1", agreed ? { agreedTerms: { version: termsVersion } } : {});
    // Seal the record directly, as it was stored before: any birth date, the old 13+ rule.
    const cipher = new FakeCipher();
    const sealed = await cipher.seal(Buffer.from(JSON.stringify({ ...adult, birthDate }), "utf8"), "personalDetails/u1");
    s.store.put("personalDetails/u1", { ciphertext: sealed.ciphertext, key: sealed.key, format: 1 });
  }

  it("an adult with details and the agreement gets both claims, and refreshes", async () => {
    await existing("1995-04-02");
    const res = await s.call("bare", "GET", "/v1/me/personal/status");
    expect(res.json()).toEqual({ complete: true, required: true, refreshToken: true });
    expect(s.users.claims.get("u1")).toEqual({ ageOk: true, terms: termsVersion });
  });

  it("once the token carries them, the status says nothing to refresh", async () => {
    await existing("1995-04-02");
    const res = await s.call("token", "GET", "/v1/me/personal/status");
    expect(res.json()).toEqual({ complete: true, required: true });
    expect(s.users.claims.size).toBe(0);
  });

  it("an existing 17-year-old gets no ageOk (only the terms claim): still read-only", async () => {
    await existing("2009-06-01");
    const res = await s.call("bare", "GET", "/v1/me/personal/status");
    expect(res.json().refreshToken).toBe(true);
    expect(s.users.claims.get("u1")).toEqual({ terms: termsVersion });
    const w = await s.call("noage", "POST", "/v1/posts", {});
    expect(w.statusCode).toBe(403);
    expect(Object.keys(w.json().error.fields)).toEqual(["age"]);
  });

  it("an existing account that never agreed to the terms gets only ageOk", async () => {
    await existing("1995-04-02", false);
    await s.call("bare", "GET", "/v1/me/personal/status");
    expect(s.users.claims.get("u1")).toEqual({ ageOk: true });
  });

  it("an account with no details and no agreement gets nothing", async () => {
    const res = await s.call("bare", "GET", "/v1/me/personal/status");
    expect(res.json()).toEqual({ complete: false, required: true });
    expect(s.users.claims.size).toBe(0);
  });

  it("someone else's records never earn the caller a claim", async () => {
    // u1 has an adult birth date and an agreement on file; u2 has nothing.
    await existing("1995-04-02");
    const res = await s.call("bare", "GET", "/v1/me/personal/status", undefined, "u2");
    expect(res.json().refreshToken).toBeUndefined();
    expect(s.users.claims.has("u2")).toBe(false);
    expect(s.users.claims.has("u1")).toBe(false);
  });

  it("a record copied to the caller's path doesn't open, and earns nothing (the path is the cipher's context)", async () => {
    await existing("1995-04-02");
    s.store.put("personalDetails/u2", s.store.doc("personalDetails/u1")!);
    const res = await s.call("bare", "GET", "/v1/me/personal/status", undefined, "u2");
    expect(res.statusCode).toBe(200);
    expect(s.users.claims.has("u2")).toBe(false);
  });

  it("opens the birth date only while the token lacks ageOk (incomplete token)", async () => {
    await existing("1995-04-02");
    const open = () => (s.cipher as FakeCipher).calls.open;
    await s.call("token", "GET", "/v1/me/personal/status");
    expect(open()).toBe(0);
    await s.call("noage", "GET", "/v1/me/personal/status");
    expect(open()).toBe(1);
    expect(s.users.claims.get("u1")).toEqual({ ageOk: true });
  });

  it("a decrypt failure grants no age claim, doesn't break status, and still grants terms (F9)", async () => {
    await existing("1995-04-02");
    s.cipher.open = async () => {
      throw new Error("kms down");
    };
    const res = await s.call("bare", "GET", "/v1/me/personal/status");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ complete: true, required: true, refreshToken: true });
    expect(s.users.claims.get("u1")).toEqual({ terms: termsVersion });
  });

  it("a decrypt failure on a record with nothing else to grant is a plain 200", async () => {
    await existing("1995-04-02", false);
    s.cipher.open = async () => {
      throw new Error("kms down");
    };
    const res = await s.call("bare", "GET", "/v1/me/personal/status");
    expect(res.statusCode).toBe(200);
    expect(s.users.claims.size).toBe(0);
  });
});
