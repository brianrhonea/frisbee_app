// Group tournaments, following the groupTournaments, games and
// tournamentDirectory rules in firebase/firestore.rules: one test per
// conjunct of each allow.
import { groupEngine } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
let store: FakeStore;
type Method = "POST" | "PUT" | "DELETE";
let call: (method: Method, url: string, body?: object, uid?: string) => Promise<{ status: number; json: () => any }>;
let unauthenticated: (method: Method, url: string, body?: object) => Promise<number>;

const base = "/v1/teams/g1/group-tournaments";
const tPath = (id: string) => `teams/g1/groupTournaments/${id}`;
const gPath = (id: string, g: string) => `teams/g1/groupTournaments/${id}/games/${g}`;

const team = (id: string, players: string[], captainId: string | null = players[0] ?? null) => ({
  id,
  name: `Team ${id}`,
  captainId,
  playerIds: players,
  playerNames: Object.fromEntries(players.map((u) => [u, `Name ${u}`])),
});
const draft = (o: Record<string, unknown> = {}) => ({
  name: "Fall Hat",
  settings: { startsAt: "2026-11-21T14:00:00.000Z", format: "singleElim", fields: 2, laterDays: ["2026-11-22T15:00:00.000Z"] },
  teams: [team("t1", ["a1", "a2"]), team("t2", ["b1"]), team("t3", ["c1"]), team("t4", ["d1"])],
  ...o,
});

beforeEach(() => {
  store = new FakeStore(() => now);
  const teams = new FakeTeamRepository();
  teams.store = store;
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams, store, media: new FakeMediaStorage(), now: () => now, writeLimits: false });
  call = async (method, url, body, uid = "org") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer token:${uid}` } });
    return { status: res.statusCode, json: () => res.json() };
  };
  unauthenticated = async (method, url, body) => (await app.inject({ method, url, ...(body && { payload: body }) })).statusCode;
  const members = ["owner", "org", "player", "a1", "a2", "b1", "c1", "d1"];
  store.put("teams/g1", {
    kind: "community",
    ownerId: "owner",
    memberIds: members,
    members: Object.fromEntries(members.map((m) => [m, m === "owner" ? "owner" : "player"])),
    memberNames: { a1: "Alex", b1: "Bo" },
    memberPerms: { org: ["manageEvents"], player: ["manageTeam"] },
  });
  store.put("teams/team1", { ownerId: "owner", memberIds: ["owner"], members: { owner: "owner" } });
});

async function created(body = draft()) {
  const res = await call("POST", base, body);
  expect(res.status).toBe(201);
  return res.json().id as string;
}
async function published(body = draft()) {
  const id = await created(body);
  expect((await call("POST", `${base}/${id}/schedule`, body)).status).toBe(200);
  return id;
}
const game = (id: string, g: string) => store.doc(gPath(id, g))!;

describe("create (allow create)", () => {
  it("signedIn()", async () => {
    expect(await unauthenticated("POST", base, draft())).toBe(401);
  });
  it("isGroup(team())", async () => {
    expect((await call("POST", "/v1/teams/team1/group-tournaments", draft(), "owner")).status).toBe(412);
  });
  it("can(team(), 'manageEvents')", async () => {
    expect((await call("POST", base, draft(), "player")).status).toBe(403);
    expect((await call("POST", base, draft(), "stranger")).status).toBe(403);
    expect((await call("POST", base, draft(), "owner")).status).toBe(201);
  });
  it("createdBy == uid() and createdAt == request.time, never from the body", async () => {
    expect((await call("POST", base, { ...draft(), createdBy: "owner" })).status).toBe(400);
    const id = await created();
    expect(store.doc(tPath(id))).toMatchObject({ createdBy: "org", createdAt: new Date(now) });
  });
  it("keys().hasOnly([...]) and the app's stored shape", async () => {
    expect((await call("POST", base, { ...draft(), status: "done" })).status).toBe(400);
    const id = await created();
    const t = store.doc(tPath(id))!;
    expect(Object.keys(t).sort()).toEqual(["captains", "createdAt", "createdBy", "eventId", "name", "participantIds", "settings", "status", "teams"]);
    expect(t.status).toBe("setup");
    expect(t.eventId).toBeNull();
    const s = t.settings as Record<string, unknown>;
    expect(s.startsAt).toBeInstanceOf(Date);
    expect((s.laterDays as unknown[])[0]).toBeInstanceOf(Date);
    expect(s.idealEndsAt).toBeNull();
    expect(s).toMatchObject({ format: "singleElim", playersOnField: 5, poolCount: 2, gameMinutes: 40, scoring: "points" });
  });
  it("name is a string of 1 to 100 characters", async () => {
    expect((await call("POST", base, draft({ name: " " }))).status).toBe(400);
    expect((await call("POST", base, draft({ name: "x".repeat(101) }))).status).toBe(400);
  });
  it("eventId is null or a string of up to 100", async () => {
    expect((await call("POST", base, draft({ eventId: "x".repeat(101) }))).status).toBe(400);
    expect((await call("POST", base, draft({ eventId: 7 }))).status).toBe(400);
    const id = await created(draft({ eventId: "ev1" }));
    expect(store.doc(tPath(id))!.eventId).toBe("ev1");
  });
  it("settings is map", async () => {
    expect((await call("POST", base, draft({ settings: "fast" }))).status).toBe(400);
  });
  it("teams is a list of at most 64", async () => {
    const many = Array.from({ length: 65 }, (_, i) => team(`x${i}`, []));
    expect((await call("POST", base, draft({ teams: many }))).status).toBe(400);
    expect((await call("POST", base, draft({ teams: many.slice(0, 64) }))).status).toBe(201);
  });
  it("participantIds has at most 1000 players", async () => {
    const big = Array.from({ length: 2 }, (_, t) => team(`x${t}`, Array.from({ length: 501 }, (_, i) => `p${t}_${i}`), null));
    expect((await call("POST", base, draft({ teams: big }))).status).toBe(400);
  });
  it("participantIds are all group members", async () => {
    expect((await call("POST", base, draft({ teams: [team("t1", ["a1", "stranger"])] }))).status).toBe(412);
  });
  it("captains are participants, and computed from the teams", async () => {
    expect((await call("POST", base, draft({ teams: [team("t1", ["a1"], "b1")] }))).status).toBe(400);
    const id = await created(draft({ teams: [team("t1", ["a1", "a2"], "a2"), team("t2", ["b1"], null)] }));
    const t = store.doc(tPath(id))!;
    expect(t.captains).toEqual({ t1: "a2" });
    expect(t.participantIds).toEqual(["a1", "a2", "b1"]);
    // Names come from the group where it has them.
    expect((t.teams as any[])[0].playerNames).toEqual({ a1: "Alex", a2: "Name a2" });
  });
  it("writes the public listing (validTournamentListing)", async () => {
    const id = await created();
    const l = store.doc(`tournamentDirectory/g1_${id}`)!;
    expect(Object.keys(l).sort()).toEqual(["endsOn", "format", "groupId", "name", "startsAt", "status", "tournamentId"]);
    expect(l).toMatchObject({ groupId: "g1", tournamentId: id, name: "Fall Hat", status: "setup", format: "singleElim" });
    expect(l.startsAt).toBeInstanceOf(Date);
    expect(l.endsOn).toEqual(new Date("2026-11-22T15:00:00.000Z"));
  });
});

describe("save (allow update)", () => {
  it("isGroup, manageEvents, and the tournament exists", async () => {
    const id = await created();
    expect((await call("PUT", `${base}/${id}`, draft(), "player")).status).toBe(403);
    expect(await unauthenticated("PUT", `${base}/${id}`, draft())).toBe(401);
    expect((await call("PUT", `${base}/ghost`, draft())).status).toBe(404);
    expect((await call("PUT", `/v1/teams/team1/group-tournaments/${id}`, draft(), "owner")).status).toBe(412);
  });
  it("createdBy and createdAt never change; captains are replaced whole", async () => {
    const id = await created();
    expect((await call("PUT", `${base}/${id}`, draft({ name: "Winter Hat", teams: [team("t1", ["a1"]), team("t2", ["b1"], null)] }), "owner")).status).toBe(204);
    const t = store.doc(tPath(id))!;
    expect(t).toMatchObject({ name: "Winter Hat", createdBy: "org", createdAt: new Date(now), captains: { t1: "a1" } });
    expect(store.doc(`tournamentDirectory/g1_${id}`)!.name).toBe("Winter Hat");
  });
  it("validTournament on every save", async () => {
    const id = await created();
    expect((await call("PUT", `${base}/${id}`, draft({ teams: [team("t1", ["stranger"])] }))).status).toBe(412);
    expect((await call("PUT", `${base}/${id}`, draft({ name: "" }))).status).toBe(400);
  });
  it("after publishing, the teams can't change without publishing again", async () => {
    const id = await published();
    expect((await call("PUT", `${base}/${id}`, draft({ teams: draft().teams.slice(0, 3) }))).status).toBe(412);
    expect((await call("PUT", `${base}/${id}`, draft({ name: "Renamed" }))).status).toBe(204);
    expect(store.doc(tPath(id))!.status).toBe("scheduled");
  });
});

describe("publish (games: allow create, delete; tournament update)", () => {
  it("organizers only, and needs two teams", async () => {
    const id = await created();
    expect((await call("POST", `${base}/${id}/schedule`, draft(), "a1")).status).toBe(403);
    expect((await call("POST", `${base}/${id}/schedule`, draft({ teams: [team("t1", ["a1"])] }))).status).toBe(412);
    expect((await call("POST", `${base}/ghost/schedule`, draft())).status).toBe(404);
  });
  it("writes the engine's games as the app stores them, and marks it scheduled", async () => {
    const id = await published();
    const plan = groupEngine.scheduleFor(["t1", "t2", "t3", "t4"], { ...draft().settings, poolCount: 2, playersOnField: 5, gameMinutes: 40, breakMinutes: 10, scoreCap: 11, timeoutsPerHalf: 1, idealEndsAt: null, scoring: "points" } as any);
    const ids = store.list(`teams/g1/groupTournaments/${id}/games`, 100);
    expect((await ids).map((g) => g.id)).toEqual(plan.games.map((g) => g.id).sort());
    const g1 = game(id, "g001");
    expect(Object.keys(g1).sort()).toEqual(
      ["field", "ifNeeded", "label", "order", "pool", "report", "round", "scoreA", "scoreB", "sourceA", "sourceB", "stage", "startsAt", "status", "teamA", "teamB"].sort(),
    );
    expect(g1.startsAt).toBeInstanceOf(Date);
    expect(g1).toMatchObject({ stage: "winners", status: "scheduled", teamA: "t1", teamB: "t4", report: null, scoreA: null });
    expect(store.doc(tPath(id))!.status).toBe("scheduled");
    expect(store.doc(`tournamentDirectory/g1_${id}`)!.status).toBe("scheduled");
  });
  it("republishing replaces every game", async () => {
    const id = await published();
    store.put(gPath(id, "g999"), { order: 99 });
    store.put(gPath(id, "g001"), { ...game(id, "g001"), status: "done", scoreA: 11, scoreB: 3 });
    expect((await call("POST", `${base}/${id}/schedule`, draft({ settings: { ...draft().settings, format: "roundRobin" } }))).status).toBe(200);
    expect(store.doc(gPath(id, "g999"))).toBeUndefined();
    expect(game(id, "g001").status).toBe("scheduled");
    expect((await store.list(`teams/g1/groupTournaments/${id}/games`, 100)).length).toBe(6);
  });
  it("a schedule too big for one transaction still lands", async () => {
    const teams = Array.from({ length: 40 }, (_, i) => team(`x${i}`, []));
    const body = draft({ teams, settings: { ...draft().settings, format: "roundRobin", laterDays: [] } });
    const id = await created(body);
    const res = await call("POST", `${base}/${id}/schedule`, body);
    expect(res.json().games).toBe(780);
    expect((await store.list(`teams/g1/groupTournaments/${id}/games`, 1000)).length).toBe(780);
  });
});

describe("delete (allow delete)", () => {
  it("can(team(), 'manageEvents'): the tournament, its games and its listing go", async () => {
    const id = await published();
    expect((await call("DELETE", `${base}/${id}`, undefined, "a1")).status).toBe(403);
    expect(await unauthenticated("DELETE", `${base}/${id}`)).toBe(401);
    expect((await call("DELETE", `${base}/${id}`)).status).toBe(204);
    expect(store.doc(tPath(id))).toBeUndefined();
    expect(store.doc(gPath(id, "g001"))).toBeUndefined();
    expect(store.doc(`tournamentDirectory/g1_${id}`)).toBeUndefined();
  });
});

describe("report()", () => {
  // g001: t1 (captain a1) v t4 (captain d1).
  const url = (id: string, g = "g001") => `${base}/${id}/games/${g}/report`;
  it("changed().hasOnly(['report', 'status']) with status 'reported'", async () => {
    const id = await published();
    const before = game(id, "g001");
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "a1")).status).toBe(204);
    const after = game(id, "g001");
    expect(after).toEqual({ ...before, status: "reported", report: { scoreA: 11, scoreB: 7, byTeam: "t1" } });
  });
  it("teamA != null && teamB != null", async () => {
    const id = await published();
    store.put(gPath(id, "g001"), { ...game(id, "g001"), teamB: null });
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "a1")).status).toBe(412);
  });
  it("status != 'done'", async () => {
    const id = await published();
    store.put(gPath(id, "g001"), { ...game(id, "g001"), status: "done", scoreA: 11, scoreB: 2 });
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "a1")).status).toBe(412);
  });
  it("report keys hasOnly scoreA, scoreB, byTeam", async () => {
    const id = await published();
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7, byTeam: "t4" }, "a1")).status).toBe(400);
  });
  it("validScore: whole numbers from 0 to 99", async () => {
    const id = await published();
    expect((await call("POST", url(id), { scoreA: 100, scoreB: 7 }, "a1")).status).toBe(400);
    expect((await call("POST", url(id), { scoreA: -1, scoreB: 7 }, "a1")).status).toBe(400);
    expect((await call("POST", url(id), { scoreA: 1.5, scoreB: 7 }, "a1")).status).toBe(400);
  });
  it("scoreA != scoreB", async () => {
    const id = await published();
    expect((await call("POST", url(id), { scoreA: 7, scoreB: 7 }, "a1")).status).toBe(400);
  });
  it("byTeam in [teamA, teamB] and captainOf(byTeam)", async () => {
    const id = await published();
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "a2")).status).toBe(403); // on t1, not captain
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "b1")).status).toBe(403); // captain of another team
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "org")).status).toBe(403);
    expect((await call("POST", url(id), { scoreA: 7, scoreB: 11 }, "d1")).status).toBe(204);
    expect(game(id, "g001").report).toEqual({ scoreA: 7, scoreB: 11, byTeam: "t4" });
    // Re-filing replaces the other captain's report.
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "a1")).status).toBe(204);
    expect(game(id, "g001").report).toEqual({ scoreA: 11, scoreB: 7, byTeam: "t1" });
  });
  it("404s for a missing tournament or game", async () => {
    const id = await published();
    expect((await call("POST", url("ghost"), { scoreA: 11, scoreB: 7 }, "a1")).status).toBe(404);
    expect((await call("POST", url(id, "nope"), { scoreA: 11, scoreB: 7 }, "a1")).status).toBe(404);
  });
});

describe("confirm()", () => {
  const url = (id: string) => `${base}/${id}/games/g001/confirm`;
  async function reported() {
    const id = await published();
    expect((await call("POST", `${base}/${id}/games/g001/report`, { scoreA: 11, scoreB: 7 }, "a1")).status).toBe(204);
    return id;
  }
  it("status == 'reported'", async () => {
    const id = await published();
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "d1")).status).toBe(412);
  });
  it("captainOf(other): only the other team's captain", async () => {
    const id = await reported();
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "a1")).status).toBe(403);
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "b1")).status).toBe(403);
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "org")).status).toBe(403);
  });
  it("d.scoreA/B == report's, status 'done', report null, only those fields", async () => {
    const id = await reported();
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 8 }, "d1")).status).toBe(412);
    const before = game(id, "g001");
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "d1")).status).toBe(204);
    expect(game(id, "g001")).toEqual({ ...before, status: "done", scoreA: 11, scoreB: 7, report: null });
  });
  it("moves the winner on in the same write (advance(): slotFilled)", async () => {
    const id = await reported();
    // The final waits on W(g001) and W(g002).
    const fin = (await store.list(`teams/g1/groupTournaments/${id}/games`, 10)).find((g) => g.data.label === "Final")!;
    expect((await call("POST", url(id), { scoreA: 11, scoreB: 7 }, "d1")).status).toBe(204);
    expect(game(id, fin.id).teamA).toBe("t1");
    expect(game(id, fin.id).teamB).toBeNull();
  });
});

describe("organizers' scores (manageEvents && validGame)", () => {
  const url = (id: string, g = "g001") => `${base}/${id}/games/${g}/score`;
  it("manageEvents", async () => {
    const id = await published();
    expect((await call("PUT", url(id), { scoreA: 11, scoreB: 7 }, "a1")).status).toBe(403);
    expect((await call("PUT", url(id), { scoreA: 11, scoreB: 7 })).status).toBe(204);
    expect(game(id, "g001")).toMatchObject({ status: "done", scoreA: 11, scoreB: 7, report: null });
  });
  it("validGame: done needs valid, untied scores", async () => {
    const id = await published();
    expect((await call("PUT", url(id), { scoreA: 7, scoreB: 7 })).status).toBe(400);
    expect((await call("PUT", url(id), { scoreA: 7, scoreB: 100 })).status).toBe(400);
  });
  it("corrects a score and the team moved on, until later games are played", async () => {
    const id = await published();
    const fin = (await store.list(`teams/g1/groupTournaments/${id}/games`, 10)).find((g) => g.data.label === "Final")!.id;
    await call("PUT", url(id), { scoreA: 11, scoreB: 7 });
    expect(game(id, fin).teamA).toBe("t1");
    expect((await call("PUT", url(id), { scoreA: 7, scoreB: 11 })).status).toBe(204);
    expect(game(id, fin).teamA).toBe("t4");
    await call("PUT", url(id, "g002"), { scoreA: 11, scoreB: 7 });
    await call("PUT", url(id, fin), { scoreA: 11, scoreB: 7 });
    expect((await call("PUT", url(id), { scoreA: 11, scoreB: 7 })).status).toBe(412);
  });
  it("teams must be known", async () => {
    const id = await published();
    const fin = (await store.list(`teams/g1/groupTournaments/${id}/games`, 10)).find((g) => g.data.label === "Final")!.id;
    expect((await call("PUT", url(id, fin), { scoreA: 11, scoreB: 7 })).status).toBe(412);
  });
});

describe("advance()", () => {
  async function confirmedWithoutMove() {
    const id = await published();
    const fin = (await store.list(`teams/g1/groupTournaments/${id}/games`, 10)).find((g) => g.data.label === "Final")!.id;
    // A confirm whose bracket update didn't land.
    store.put(gPath(id, "g001"), { ...game(id, "g001"), status: "done", scoreA: 11, scoreB: 7 });
    return { id, fin };
  }
  it("uid() in participantIds (or an organizer)", async () => {
    const { id, fin } = await confirmedWithoutMove();
    expect((await call("POST", `${base}/${id}/advance`, undefined, "player")).status).toBe(403);
    expect(game(id, fin).teamA).toBeNull();
    const res = await call("POST", `${base}/${id}/advance`, undefined, "b1");
    expect(res.status).toBe(200);
    expect(res.json().filled).toBe(1);
    expect(game(id, fin).teamA).toBe("t1");
  });
  it("changed().hasOnly(['teamA', 'teamB']) and slotFilled: only empty slots, from that game's result", async () => {
    const { id, fin } = await confirmedWithoutMove();
    store.put(gPath(id, fin), { ...game(id, fin), teamA: "t2" });
    const before = game(id, fin);
    expect((await call("POST", `${base}/${id}/advance`, undefined, "b1")).json().filled).toBe(0);
    expect(game(id, fin)).toEqual(before);
  });
  it("pool-rank seeds are organizers' (seed-bracket)", async () => {
    const body = draft({ settings: { ...draft().settings, format: "poolsSingleElim", poolCount: 2, laterDays: [] } });
    const id = await published(body);
    expect((await call("POST", `${base}/${id}/seed-bracket`)).status).toBe(412); // pools not done
    for (const g of await store.list(`teams/g1/groupTournaments/${id}/games`, 50)) {
      if (g.data.stage === "pool") store.put(gPath(id, g.id), { ...g.data, status: "done", scoreA: 11, scoreB: 5 });
    }
    expect((await call("POST", `${base}/${id}/advance`, undefined, "a1")).json().filled).toBe(0);
    expect((await call("POST", `${base}/${id}/seed-bracket`, undefined, "a1")).status).toBe(403);
    expect((await call("POST", `${base}/${id}/seed-bracket`)).status).toBe(204);
    const bracket = (await store.list(`teams/g1/groupTournaments/${id}/games`, 50)).filter((g) => g.data.stage !== "pool" && g.data.sourceA && (g.data.sourceA as any).type === "pool");
    expect(bracket.length).toBeGreaterThan(0);
    expect(bracket.every((g) => g.data.teamA !== null && g.data.teamB !== null)).toBe(true);
  });
});

describe("more conjuncts", () => {
  it("validGame's place: set on placement games, left out elsewhere", async () => {
    const body = draft({ settings: { ...draft().settings, format: "poolsPlacement", poolCount: 1, laterDays: [] } });
    const id = await published(body);
    const games = await store.list(`teams/g1/groupTournaments/${id}/games`, 50);
    expect(games.find((g) => g.data.label === "Final")!.data.place).toBe(1);
    expect(games.filter((g) => g.data.stage === "pool").every((g) => !("place" in g.data))).toBe(true);
  });
  it("the listing's endsOn is null without later days", async () => {
    const id = await created(draft({ settings: { ...draft().settings, laterDays: [] } }));
    expect(store.doc(`tournamentDirectory/g1_${id}`)!.endsOn).toBeNull();
  });
  it("signedIn() on schedules and games", async () => {
    const id = await published();
    expect(await unauthenticated("POST", `${base}/${id}/schedule`, draft())).toBe(401);
    expect(await unauthenticated("POST", `${base}/${id}/games/g001/report`, { scoreA: 11, scoreB: 7 })).toBe(401);
    expect(await unauthenticated("POST", `${base}/${id}/games/g001/confirm`, { scoreA: 11, scoreB: 7 })).toBe(401);
    expect(await unauthenticated("PUT", `${base}/${id}/games/g001/score`, { scoreA: 11, scoreB: 7 })).toBe(401);
    expect(await unauthenticated("POST", `${base}/${id}/advance`)).toBe(401);
    expect(await unauthenticated("POST", `${base}/${id}/seed-bracket`)).toBe(401);
  });
  it("a schedule's players are checked before any game is replaced", async () => {
    const id = await published();
    const before = game(id, "g001");
    expect((await call("POST", `${base}/${id}/schedule`, draft({ teams: [team("t1", ["stranger"]), team("t2", ["b1"])] }))).status).toBe(412);
    expect(game(id, "g001")).toEqual(before);
  });
});

describe("ids", () => {
  it("docIdParam on every path id", async () => {
    expect((await call("PUT", `${base}/__x__`, draft())).status).toBe(400);
    expect((await call("POST", `${base}/a/games/%2Fx/report`, { scoreA: 1, scoreB: 0 }, "a1")).status).toBe(400);
  });
});
