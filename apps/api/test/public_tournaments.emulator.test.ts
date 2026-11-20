// Visitors' tournament pages against the Firestore emulator (pnpm
// test:emulator): the real range queries (and their composite indexes'
// shapes), selects and ordering over seeded data.
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { BrowseRepository } from "../src/browse/repository.js";
import { FirestoreRateLimiter } from "../src/limits/limiter.js";
import { FirestorePublicTournamentRepository } from "../src/tournaments/public_repository.js";
import { FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const projectId = "demo-stall10";
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run with `pnpm test:emulator`.");

const firebase = initializeApp({ projectId }, "public-tournaments-emulator-test");
const db = getFirestore(firebase);
const app = buildApp({
  verifier: new FakeVerifier(),
  users: new FakeUsers(),
  teams: new FakeTeamRepository(),
  browse: { repo: {} as BrowseRepository, limiter: new FirestoreRateLimiter(db), imageUrl: (p) => p },
  publicTournaments: new FirestorePublicTournamentRepository(db),
});

const day = 24 * 60 * 60 * 1000;
const ts = (msFromNow: number) => Timestamp.fromMillis(Date.now() + msFromNow);
const get = (url: string) => app.inject({ method: "GET", url, headers: { "x-forwarded-for": "198.51.100.21" } });

const tournament = (name: string, extra: Record<string, unknown> = {}) => ({
  hostId: "club",
  hostName: "Club",
  hostKind: "organization",
  name,
  startsOn: ts(3 * day),
  endsOn: null,
  description: "",
  location: "Park",
  visibility: "public",
  entryType: "teams",
  status: "registration",
  bidFee: { amountCents: 1000, currency: "USD", instructions: "Pay Pat at pat@example.test", dueAt: null },
  kind: "tournament",
  divisions: [{ id: "open", division: "open", level: "club" }],
  createdBy: "hostUid",
  createdAt: ts(-10 * day),
  ...extra,
});

beforeAll(async () => {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, {
    method: "DELETE",
  });
  const batch = db.batch();
  batch.set(db.doc("teamDirectory/club"), { name: "Club", kind: "organization", requiresApproval: false, division: "open", level: "club", city: "" });
  // Team docs, read with a field mask (kind, requiresApproval, level): the host's agrees with its listing.
  batch.set(db.doc("teams/club"), { name: "Club", kind: "organization", requiresApproval: false, memberIds: ["hostUid"], members: { hostUid: "owner" } });
  // A listing that says open, but the group now approves members: private.
  batch.set(db.doc("teamDirectory/stale"), { name: "Stale", kind: "community", requiresApproval: false, division: "mixed", level: "pickup", city: "" });
  batch.set(db.doc("teams/stale"), { name: "Stale", kind: "community", requiresApproval: true, memberIds: ["x"] });
  batch.set(db.doc("tournaments/stale"), tournament("Stale", { hostId: "stale" }));
  batch.set(db.doc("teamDirectory/secret"), { name: "Secret", kind: "community", requiresApproval: true, division: "mixed", level: "pickup", city: "" });
  batch.set(db.doc("tournaments/soon"), tournament("Soon", { startsOn: ts(day) }));
  batch.set(db.doc("tournaments/later"), tournament("Later", { startsOn: ts(10 * day) }));
  batch.set(db.doc("tournaments/league"), tournament("League", { kind: "league", status: "scheduled", startsOn: ts(-60 * day), endsOn: ts(20 * day) }));
  batch.set(db.doc("tournaments/old"), tournament("Old", { startsOn: ts(-60 * day), endsOn: ts(-30 * day) }));
  batch.set(db.doc("tournaments/draft"), tournament("Draft", { status: "draft" }));
  batch.set(db.doc("tournaments/private"), tournament("Private", { hostId: "secret" }));
  batch.set(db.doc("tournaments/soon/divisions/open"), {
    division: "open",
    level: "club",
    settings: { format: "roundRobin", fields: 2, startsAt: ts(day) },
    maxTeams: 8,
    seeds: ["a", "b"],
    captains: { a: ["capA"] },
    placements: [],
    minRoster: null,
    teams: [],
  });
  batch.set(db.doc("tournaments/soon/entries/a"), { teamName: "Alpha", divisionId: "open", status: "accepted", captainIds: ["capA"], updatedAt: ts(0) });
  batch.set(db.doc("tournaments/soon/entries/b"), { teamName: "Bravo", divisionId: "open", status: "accepted", captainIds: ["capB"], updatedAt: ts(0) });
  batch.set(db.doc("tournaments/soon/entries/c"), { teamName: "Charlie", divisionId: "open", status: "applied", captainIds: ["capC"], updatedAt: ts(0) });
  for (const [id, order] of [["g2", 1], ["g1", 0]] as const) {
    batch.set(db.doc(`tournaments/soon/divisions/open/games/${id}`), {
      order,
      stage: "pool",
      round: order + 1,
      label: "Round robin",
      pool: "A",
      field: 1,
      startsAt: ts(day + order * 3600_000),
      teamA: "a",
      teamB: "b",
      sourceA: null,
      sourceB: null,
      status: "scheduled",
      scoreA: null,
      scoreB: null,
      report: null,
      ifNeeded: false,
    });
  }
  // Running scores (games/{id}.live), read by live.updatedAt alone.
  const liveGame = (updatedAt: Timestamp) => ({ order: 0, status: "scheduled", teamA: "a", teamB: "b", live: { scoreA: 7, scoreB: 5, startedAt: updatedAt, updatedAt, by: "capA" } });
  batch.set(db.doc("tournaments/soon/divisions/live/games/now"), liveGame(ts(-60_000)));
  batch.set(db.doc("tournaments/soon/divisions/live/games/stale"), liveGame(ts(-5 * 3600_000)));
  batch.set(db.doc("tournaments/soon/divisions/live/games/none"), { order: 1, status: "scheduled", teamA: "a", teamB: "b" });
  batch.set(db.doc("tournamentDirectory/club_gt1"), { groupId: "club", tournamentId: "gt1", name: "Hat", startsAt: ts(day), status: "setup", format: "roundRobin" });
  await batch.commit();
});

afterAll(() => deleteApp(firebase));

describe("visitors' tournament pages on Firestore", () => {
  it("lists upcoming and running published events, hiding drafts and private groups'", async () => {
    const res = await get("/v1/public/tournaments");
    expect(res.statusCode).toBe(200);
    expect(res.json().tournaments.map((t: { id: string }) => t.id)).toEqual(["league", "soon", "later"]);
  });

  it("reads a page: games in order, accepted entries, no captains or fee instructions", async () => {
    const res = await get("/v1/public/tournaments/soon");
    expect(res.statusCode).toBe(200);
    const page = res.json();
    expect(page.games.map((g: { id: string }) => g.id)).toEqual(["g1", "g2"]);
    expect(page.entries.map((e: { teamName: string }) => e.teamName)).toEqual(["Alpha", "Bravo"]);
    expect(page.names).toEqual({ a: "Alpha", b: "Bravo" });
    expect(page.tournament.bidFee).toEqual({ amountCents: 1000, currency: "USD", dueAt: null });
    const text = JSON.stringify(page);
    for (const hidden of ["capA", "capB", "Charlie", "pat@example.test", "hostUid"]) expect(text).not.toContain(hidden);
  });

  it("finds the games whose running score was updated lately, without an index of its own", async () => {
    const repo = new FirestorePublicTournamentRepository(db);
    const games = await repo.liveGames("soon", "live", new Date(Date.now() - 3 * 3600_000));
    expect(games.map((g) => g.id)).toEqual(["now"]);
    expect(games[0].data.live).toMatchObject({ scoreA: 7, scoreB: 5 });
  });

  it("404s drafts and private groups' events", async () => {
    expect((await get("/v1/public/tournaments/draft")).statusCode).toBe(404);
    expect((await get("/v1/public/tournaments/private")).statusCode).toBe(404);
    expect((await get("/v1/public/tournaments/stale")).statusCode).toBe(404);
  });

  it("reads a group tournament's listing", async () => {
    const res = await get("/v1/public/group-tournaments/club/gt1");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ groupId: "club", tournamentId: "gt1", name: "Hat", endsOn: null });
  });
});
