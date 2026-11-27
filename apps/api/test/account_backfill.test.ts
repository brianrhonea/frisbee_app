// The one-off claim backfill (src/account/backfill.ts): dry run by default,
// idempotent, grants only what the records earn, never for a minor.
import { termsVersion } from "@stall10/shared";
import { describe, expect, it } from "vitest";
import { type BackfillUser, backfillClaims } from "../src/account/backfill.js";
import { type ClaimsAuth } from "../src/account/claims.js";
import { AccountGate } from "../src/account/gate.js";
import { PersonalService } from "../src/personal/service.js";
import { FakeCipher, FakeStore, FakeUsers } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12);

async function world() {
  const store = new FakeStore(() => now);
  const cipher = new FakeCipher();
  const users = new FakeUsers();
  const births = new PersonalService(store, users, cipher, () => now);
  const gate = new AccountGate(store, users, births, () => now);
  const claims = new Map<string, Record<string, unknown>>();
  const writes: string[] = [];
  const auth: ClaimsAuth = {
    async getUser(uid) {
      return { customClaims: claims.get(uid) ?? null };
    },
    async setCustomUserClaims(uid, c) {
      writes.push(uid);
      claims.set(uid, c);
    },
  };
  const seed = async (uid: string, birthDate: string | null, agreed: boolean) => {
    if (birthDate) {
      const sealed = await cipher.seal(Buffer.from(JSON.stringify({ birthDate }), "utf8"), `personalDetails/${uid}`);
      store.put(`personalDetails/${uid}`, { ciphertext: sealed.ciphertext, key: sealed.key, format: 1 });
    }
    store.put(`users/${uid}`, agreed ? { agreedTerms: { version: termsVersion } } : {});
  };
  const list = async function* (): AsyncGenerator<BackfillUser> {
    for (const uid of ["adult", "agreed", "minor", "nothing", "done", "staff"]) yield { uid, customClaims: claims.get(uid) ?? null };
  };
  await seed("adult", "1995-04-02", true);
  await seed("agreed", null, true);
  await seed("minor", "2009-06-01", true);
  await seed("nothing", null, false);
  await seed("done", "1990-01-01", true);
  claims.set("done", { ageOk: true, terms: termsVersion });
  await seed("staff", "1990-01-01", false);
  claims.set("staff", { staff: true });
  for (const uid of ["adult", "done", "minor", "agreed"]) store.put(`profiles/${uid}`, { name: uid });
  return { gate, auth, claims, writes, list, cipher, store };
}

describe("claim backfill", () => {
  it("a dry run reports what it would do and writes nothing", async () => {
    const w = await world();
    const r = await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: false });
    expect(r).toMatchObject({ scanned: 6, changed: 4, grantsAgeOk: 2, grantsTerms: 3, unchanged: 2, minors: 1, applied: false });
    expect(w.writes).toEqual([]);
  });

  it("apply sets exactly what the records earn, keeps other claims, and skips minors", async () => {
    const w = await world();
    const r = await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: true });
    expect(r.writeFailures).toEqual([]);
    expect(w.claims.get("adult")).toEqual({ ageOk: true, terms: termsVersion });
    expect(w.claims.get("agreed")).toEqual({ terms: termsVersion });
    expect(w.claims.get("minor")).toEqual({ terms: termsVersion });
    expect(w.claims.has("nothing")).toBe(false);
    expect(w.claims.get("staff")).toEqual({ staff: true, ageOk: true });
  });

  it("D-1317: marks adult:true on the profile of everyone who has or earns ageOk, nobody else", async () => {
    const w = await world();
    const dry = await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: false });
    expect(dry).toMatchObject({ adultMarked: 2, adultNoProfile: 1 });
    expect(w.store.doc("profiles/adult")).toEqual({ name: "adult" });
    const r = await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: true });
    expect(r).toMatchObject({ adultMarked: 2, adultNoProfile: 1, writeFailures: [] });
    expect(w.store.doc("profiles/adult")).toEqual({ name: "adult", adult: true });
    expect(w.store.doc("profiles/done")).toEqual({ name: "done", adult: true });
    expect(w.store.doc("profiles/minor")).toEqual({ name: "minor" });
    expect(w.store.doc("profiles/agreed")).toEqual({ name: "agreed" });
    expect(w.store.doc("profiles/staff")).toBeUndefined();
    const again = await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: true });
    expect(again).toMatchObject({ adultMarked: 0, adultNoProfile: 1 });
  });

  it("is idempotent: a second run changes and writes nothing", async () => {
    const w = await world();
    await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: true });
    const before = w.writes.length;
    const again = await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: true });
    expect(again.changed).toBe(0);
    expect(w.writes.length).toBe(before);
  });

  it("a decrypt failure grants no age claim, is reported by uid, and doesn't stop the run", async () => {
    const w = await world();
    const open = w.cipher.open.bind(w.cipher);
    w.cipher.open = async (sealed, ctx) => {
      if (ctx.endsWith("/adult")) throw new Error("kms");
      return open(sealed, ctx);
    };
    const r = await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: true });
    expect(r.decryptFailures).toEqual(["adult"]);
    expect(w.claims.get("adult")).toEqual({ terms: termsVersion });
    expect(w.claims.get("staff")).toEqual({ staff: true, ageOk: true });
  });

  it("one failed write is reported and doesn't stop the run", async () => {
    const w = await world();
    const set = w.auth.setCustomUserClaims.bind(w.auth);
    w.auth.setCustomUserClaims = async (uid, c) => {
      if (uid === "adult") throw new Error("auth down");
      return set(uid, c);
    };
    const r = await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: true });
    expect(r.writeFailures).toEqual(["adult"]);
    expect(w.claims.get("agreed")).toEqual({ terms: termsVersion });
  });

  it("the report never carries a birth date or a name", async () => {
    const w = await world();
    const r = await backfillClaims({ users: w.list(), gate: w.gate, auth: w.auth, apply: false });
    expect(JSON.stringify(r)).not.toMatch(/19\d\d-|20\d\d-/);
  });
});
