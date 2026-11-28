// Team history against the Firestore and Auth emulators (pnpm test:emulator):
// the real FirestoreDocStore / FirestoreDocQueries calls the history makes
// (getAll with a field mask, a collection-group select, id-ordered paging),
// and GET /v1/players/:uid/team-history end to end.
// The emulator does not enforce composite or collection-group indexes, so the
// `roster.userId` collection-group query passing here does not prove the
// index in firebase/firestore.indexes.json exists; check that file separately.
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { teamHistoryGameBudget } from "@stall10/shared";
import { buildApp } from "../src/app.js";
import { FirestoreDocStore } from "../src/firestore_store.js";
import { FirestoreDocQueries } from "../src/queries.js";
import { FirestoreTeamRepository } from "../src/teams/repository.js";

const projectId = "demo-stall10";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!process.env.FIRESTORE_EMULATOR_HOST || !authHost) {
  throw new Error("Run with `pnpm test:emulator` (needs the Firestore and Auth emulators).");
}

const firebase = initializeApp({ projectId }, "team-history-emulator-test");
const db = getFirestore(firebase);
const auth = getAuth(firebase);
const store = new FirestoreDocStore(db);
const queries = new FirestoreDocQueries(db);
const app = buildApp({
  verifier: {
    async verifyIdToken(token) {
      const t = await auth.verifyIdToken(token);
      return { uid: t.uid, name: t.name as string | undefined, email: t.email, emailVerified: t.email_verified === true, ...(t.ageOk === true && { ageOk: true }), ...(typeof t.terms === "number" && { terms: t.terms }) };
    },
    async verifyAppCheck() {},
  },
  users: {
    async lookup(uid) {
      const u = await auth.getUser(uid);
      return { name: u.displayName, email: u.email };
    },
  },
  teams: new FirestoreTeamRepository(db),
  store,
  queries,
});

async function idTokenFor(uid: string, displayName: string): Promise<string> {
  await auth.createUser({ uid, displayName, email: `${uid}@x.test`, emailVerified: true });
  const custom = await auth.createCustomToken(uid, { ageOk: true, terms: 1 });
  const res = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token: custom, returnSecureToken: true }),
  });
  return ((await res.json()) as { idToken: string }).idToken;
}

const pad = (i: number) => `g${String(i).padStart(4, "0")}`;
const point = (spot: string) => ({
  line: [spot, "other"],
  startedOn: "offense",
  result: "weScored",
  actions: [{ kind: "goal", playerId: spot, throwerId: "other" }],
});
const game = (spot: string, date: string) => ({ opponent: "Them", date: Timestamp.fromDate(new Date(date)), gameTo: 15, points: [point(spot)] });
const team = (name: string, extra: Record<string, unknown> = {}) => ({
  name,
  kind: "team",
  level: "club",
  ownerId: "o",
  memberIds: ["o"],
  members: { o: "owner" },
  ...extra,
});

/** Writes [n] games under teams/[teamId]/statsGames, the first [recent] dated 2026 and the rest 2025. */
async function seedGames(teamId: string, spot: string, n: number, recent: number) {
  for (let from = 0; from < n; from += 200) {
    const b = db.batch();
    for (let i = from; i < Math.min(n, from + 200); i++) {
      b.set(db.doc(`teams/${teamId}/statsGames/${pad(i)}`), game(spot, i < recent ? "2026-05-01T12:00:00Z" : "2025-05-01T12:00:00Z"));
    }
    await b.commit();
  }
}

const tokens: Record<string, string> = {};
const get = (uid: string, as: string) =>
  app.inject({ method: "GET", url: `/v1/players/${uid}/team-history`, headers: { authorization: `Bearer ${tokens[as]}` } });

beforeAll(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
  await fetch(`http://${authHost}/emulator/v1/projects/${projectId}/accounts`, { method: "DELETE" });
  for (const u of ["pat", "stranger", "blocked", "blocker"]) tokens[u] = await idTokenFor(u, u);

  await db.doc("profiles/pat").set({ name: "Pat", username: "pat" });
  // Aaa: a team Pat is on, 250 games (all fit the budget). Bbb: a team Pat left, 200 games, 150 dated 2026.
  await db.doc("teams/aaa").set(team("Aaa Club", { memberIds: ["o", "pat"], members: { o: "owner", pat: "player" } }));
  await db.doc("teams/aaa/roster/p1").set({ name: "Pat P", number: 7, userId: "pat", secret: "x" });
  await db.doc("teams/aaa/roster/p2").set({ name: "Someone Else", userId: "zed" });
  await seedGames("aaa", "p1", 250, 250);
  await db.doc("teams/bbb").set(team("Bbb College", { level: "college" }));
  await db.doc("teams/bbb/roster/q1").set({ name: "Pat Q", userId: "pat" });
  await seedGames("bbb", "q1", 200, 150);
  // A youth team, hidden from strangers.
  await db.doc("teams/yth").set(team("Youth Team", { level: "youth" }));
  await db.doc("teams/yth/roster/y1").set({ name: "Pat Y", userId: "pat" });
  await db.doc("teams/yth/statsGames/g0000").set(game("y1", "2026-05-01T12:00:00Z"));
  // Blocks: written on both sides, as PUT /v1/me/blocks/:uid does.
  await db.doc("users/blocker/blocks/pat").set({ mine: true });
  await db.doc("users/pat/blocks/blocker").set({ mine: false });
  await db.doc("users/pat/blocks/blocked").set({ mine: true });
  await db.doc("users/blocked/blocks/pat").set({ mine: false });
}, 120_000);

afterAll(async () => {
  await app.close();
  await deleteApp(firebase);
});

describe("DocStore.getAll with a field mask", () => {
  it("returns only the masked fields, null for a missing document, in order", async () => {
    const got = await store.getAll(["teams/aaa", "teams/none", "teams/bbb"], ["name", "level", "memberIds"]);
    expect(got[0]).toEqual({ name: "Aaa Club", level: "club", memberIds: ["o", "pat"] });
    expect(got[1]).toBeNull();
    expect(got[2]).toEqual({ name: "Bbb College", level: "college", memberIds: ["o"] });
  });

  it("returns the whole document without a mask", async () => {
    const [full] = await store.getAll(["teams/aaa"]);
    expect(full).toMatchObject({ ownerId: "o", members: { o: "owner", pat: "player" } });
  });
});

describe("DocQueries.group with fields", () => {
  it("finds a user's roster spots across teams, with only the selected fields", async () => {
    const rows = await queries.group!("roster", 51, { userId: "pat" }, ["name", "number"]);
    const by = Object.fromEntries(rows.map((r) => [r.path, r.data]));
    expect(Object.keys(by).sort()).toEqual(["teams/aaa/roster/p1", "teams/bbb/roster/q1", "teams/yth/roster/y1"]);
    // userId (the filter) and secret are not selected, so they are not returned.
    expect(by["teams/aaa/roster/p1"]).toEqual({ name: "Pat P", number: 7 });
    expect(by["teams/bbb/roster/q1"]).toEqual({ name: "Pat Q" });
  });

  it("honours the limit and returns whole documents without fields", async () => {
    expect(await queries.group!("roster", 2, { userId: "pat" })).toHaveLength(2);
    const [one] = await queries.group!("roster", 5, { userId: "zed" });
    expect(one!.data).toEqual({ name: "Someone Else", userId: "zed" });
  });
});

describe("DocQueries.fields paging", () => {
  it("pages in document-id order across pages with the after cursor, only the listed fields", async () => {
    const col = "teams/aaa/statsGames";
    const ids: string[] = [];
    let after: string | undefined;
    let pages = 0;
    for (;;) {
      const page = await queries.fields(col, ["date"], 100, undefined, after);
      pages++;
      for (const d of page) {
        expect(Object.keys(d.data)).toEqual(["date"]);
        expect(d.data.date).toBeInstanceOf(Date);
      }
      ids.push(...page.map((d) => d.id));
      if (page.length < 100) break;
      after = page[page.length - 1]!.id;
    }
    expect(pages).toBe(3);
    expect(ids).toEqual(Array.from({ length: 250 }, (_, i) => pad(i)));
  });

  it("returns nothing after the last id", async () => {
    expect(await queries.fields("teams/aaa/statsGames", ["date"], 10, undefined, pad(249))).toEqual([]);
  });
});

describe("GET /v1/players/:uid/team-history", () => {
  it("self: every linked team, current first, with real season totals and partial only on the cut-short team", async () => {
    const res = await get("pat", "pat");
    expect(res.statusCode).toBe(200);
    const { teams } = res.json() as { teams: Array<Record<string, any>> };
    expect(teams.map((t) => t.teamName)).toEqual(["Aaa Club", "Bbb College", "Youth Team"]);
    const [aaa, bbb] = teams;
    expect(aaa!.spot).toEqual({ id: "p1", name: "Pat P", number: 7 });
    expect(aaa!.current).toBe(true);
    // 250 games over thirteen 20-game pages, all within the budget: not partial.
    expect(aaa!.seasons["2026"].games).toBe(250);
    expect(aaa).not.toHaveProperty("partial");
    // Budget 400 - 250 = 150 left: Bbb counts its first 150 ids (the 2026 ones), flagged partial.
    expect(teamHistoryGameBudget).toBe(400);
    expect(bbb!.current).toBe(false);
    expect(bbb!.seasons["2026"].games).toBe(150);
    expect(bbb!.seasons).not.toHaveProperty("2025");
    expect(bbb!.partial).toBe(true);
    expect(JSON.stringify(res.json())).not.toContain("zed");
  });

  it("a stranger sees a public club team but not the youth team", async () => {
    const res = await get("pat", "stranger");
    expect(res.statusCode).toBe(200);
    const names = (res.json() as { teams: Array<{ teamName: string }> }).teams.map((t) => t.teamName);
    expect(names).toEqual(["Aaa Club", "Bbb College"]);
  });

  it("a blocked caller, and one who blocked the player, get an empty history", async () => {
    expect((await get("pat", "blocked")).json()).toEqual({ teams: [] });
    expect((await get("pat", "blocker")).json()).toEqual({ teams: [] });
  });
});
