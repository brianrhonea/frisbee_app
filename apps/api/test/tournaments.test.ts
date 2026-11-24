// Hosted tournaments and leagues, following `match /tournaments/{id}` in
// firestore.rules (one case per conjunct) and the app's own checks.
import { type EngineGame, scheduleFor, engineSettings } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { type DocQueries, listDocQueries } from "../src/queries.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
let store: FakeStore;
/** Collections the service queried, to check callers are authorized before any list. */
let queried: string[];
type Res = { status: number; json: () => any };
let call: (method: "GET" | "POST" | "PUT" | "PATCH" | "DELETE", url: string, body?: object, uid?: string) => Promise<Res>;

const iso = (y: number, m: number, d: number, h = 0) => new Date(Date.UTC(y, m, d, h)).toISOString();
const settings = {
  format: "roundRobin",
  playersOnField: 7,
  poolCount: 2,
  gameMinutes: 60,
  breakMinutes: 10,
  scoreCap: 15,
  timeoutsPerHalf: 2,
  fields: 2,
  startsAt: iso(2026, 11, 5, 9),
  idealEndsAt: null,
  laterDays: [],
  scoring: "points",
};
const details = (o: Record<string, unknown> = {}) => ({
  name: "Spring Fling",
  description: "",
  location: "Park",
  startsOn: iso(2026, 11, 5),
  endsOn: null,
  visibility: "public",
  bidFee: null,
  teamEntry: false,
  teamFee: null,
  season: null,
  draftMode: "balanced",
  format: { settings, level: "club", maxTeams: 8, minRoster: null },
  divisions: ["mixed"],
  ...o,
});
const hosting = (o: Record<string, unknown> = {}) => ({ hostId: "host", kind: "tournament", entryType: "teams", ...details(), ...o });

const code = (r: Res) => r.json().error?.code;
const team = (name: string, captain: string, o: Record<string, unknown> = {}) => ({
  name,
  kind: "team",
  division: "mixed",
  level: "club",
  ownerId: captain,
  members: { [captain]: "owner", [`${captain}2`]: "player" },
  memberIds: [captain, `${captain}2`],
  ...o,
});

beforeEach(() => {
  store = new FakeStore(() => now);
  queried = [];
  const list = listDocQueries(store);
  const queries: DocQueries = {
    ids: (c, limit, where) => (queried.push(c), list.ids(c, limit, where)),
    fields: (c, f, limit, where) => (queried.push(c), list.fields(c, f, limit, where)),
  };
  const app = buildApp({
    verifier: new FakeVerifier(),
    users: new FakeUsers(),
    teams: new FakeTeamRepository(),
    store,
    queries,
    media: new FakeMediaStorage(),
    now: () => now,
    writeLimits: false,
  });
  call = async (method, url, body, uid = "mgr") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer token:${uid}` } });
    return { status: res.statusCode, json: () => res.json() };
  };
  store.put("teams/host", {
    name: "Host Club",
    kind: "community",
    ownerId: "owner",
    members: { owner: "owner", mgr: "player", fan: "player" },
    memberIds: ["owner", "mgr", "fan"],
    memberPerms: { mgr: ["manageEvents"] },
  });
  store.put("teams/red", team("Red", "cap"));
  store.put("teams/blue", team("Blue", "bcap"));
  store.put("teams/green", team("Green", "gcap"));
  for (const t of ["red", "blue", "green"]) for (let i = 0; i < 7; i++) store.put(`teams/${t}/roster/p${i}`, { name: `P${i}` });
});

async function host(o: Record<string, unknown> = {}) {
  const res = await call("POST", "/v1/tournaments", hosting(o));
  expect(res.status).toBe(201);
  const id = res.json().id as string;
  return { id, div: (store.doc(`tournaments/${id}`)?.divisions as Array<{ id: string }>)[0].id };
}
async function open(o: Record<string, unknown> = {}) {
  const t = await host(o);
  expect((await call("PUT", `/v1/tournaments/${t.id}/status`, { status: "registration" })).status).toBe(204);
  return t;
}
async function enter(id: string, div: string, teamId: string, captain: string) {
  return call("PUT", `/v1/tournaments/${id}/entries/${teamId}`, { divisionId: div, captainIds: [captain] }, captain);
}
async function accepted(teams: Array<[string, string]>) {
  const t = await open();
  for (const [teamId, cap] of teams) {
    expect((await enter(t.id, t.div, teamId, cap)).status).toBe(200);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/${teamId}/status`, { status: "accepted" })).status).toBe(204);
  }
  return t;
}
const gameBody = (g: EngineGame) => ({
  id: g.id,
  order: g.order,
  stage: g.stage,
  round: g.round,
  label: g.label,
  pool: g.pool,
  field: g.field,
  startsAt: g.startsAt?.toISOString() ?? null,
  teamA: g.teamA,
  teamB: g.teamB,
  sourceA: g.sourceA,
  sourceB: g.sourceB,
  ifNeeded: g.ifNeeded,
  ...(g.place != null && { place: g.place }),
});
const plan = (seeds: string[], format = "roundRobin") =>
  scheduleFor(seeds, engineSettings({ ...settings, format })).games.map(gameBody);

describe("hosting (create: manages, createdBy, createdAt, validHosted, officialHost)", () => {
  it("manages(): only the host's members with Manage events", async () => {
    expect((await call("POST", "/v1/tournaments", hosting(), "fan")).status).toBe(403);
    expect((await call("POST", "/v1/tournaments", hosting(), "stranger")).status).toBe(403);
    expect((await call("POST", "/v1/tournaments", hosting({ hostId: "ghost" }))).status).toBe(404);
  });

  it("writes the app's document: createdBy the caller, createdAt the server's time, host details from the team, a draft", async () => {
    const { id, div } = await host();
    const t = store.doc(`tournaments/${id}`) as Record<string, unknown>;
    expect(Object.keys(t).sort()).toEqual(
      [
        "hostId", "hostName", "hostKind", "hostOfficial", "name", "startsOn", "endsOn", "description", "location", "visibility",
        "entryType", "status", "bidFee", "teamEntry", "teamFee", "kind", "season", "draftMode", "inviteReplyDays", "entryDeadline", "director", "divisions", "format", "createdBy", "createdAt",
      ].sort(),
    );
    expect(t).toMatchObject({ createdBy: "mgr", createdAt: new Date(now), hostName: "Host Club", hostKind: "community", hostOfficial: false, status: "draft" });
    expect(t.startsOn).toBeInstanceOf(Date);
    expect(store.doc(`tournaments/${id}/divisions/${div}`)).toMatchObject({ division: "mixed", level: "club", maxTeams: 8, seeds: [], captains: {}, placements: [], teams: [] });
  });

  it("extra keys in the body are refused (hasOnly), so createdBy can't be forged", async () => {
    expect((await call("POST", "/v1/tournaments", { ...hosting(), createdBy: "owner" })).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", { ...hosting(), status: "live" })).status).toBe(400);
  });

  it("officialHost(): the badge comes only from an official host team", async () => {
    const { id } = await host();
    expect(store.doc(`tournaments/${id}`)?.hostOfficial).toBe(false);
    store.put("teams/host", { ...store.doc("teams/host"), official: true });
    const b = await host();
    expect(store.doc(`tournaments/${b.id}`)?.hostOfficial).toBe(true);
  });

  it("teamEntry only when players sign up", async () => {
    expect((await call("POST", "/v1/tournaments", hosting({ teamEntry: true }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ teamEntry: true, entryType: "players" }))).status).toBe(201);
  });

  it("validBidFee(): amount 0 to 10,000,000 cents, a three-letter currency, instructions up to 500, dueAt a date", async () => {
    const fee = { amountCents: 25000, currency: "USD", instructions: "Venmo", dueAt: iso(2026, 11, 1) };
    expect((await call("POST", "/v1/tournaments", hosting({ bidFee: fee }))).status).toBe(201);
    expect((await call("POST", "/v1/tournaments", hosting({ bidFee: { ...fee, amountCents: 10_000_001 } }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ bidFee: { ...fee, amountCents: -1 } }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ bidFee: { ...fee, amountCents: 1.5 } }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ bidFee: { ...fee, currency: "usd" } }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ bidFee: { ...fee, instructions: "x".repeat(501) } }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ bidFee: { ...fee, dueAt: "soon" } }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ bidFee: { ...fee, extra: 1 } }))).status).toBe(400);
  });

  it("the team spot fee follows the same rules and is needed with a fee", async () => {
    const fee = { amountCents: 1000, currency: "USD", instructions: "", dueAt: null };
    const players = { entryType: "players", teamEntry: true, bidFee: fee };
    expect((await call("POST", "/v1/tournaments", hosting(players))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ ...players, teamFee: { ...fee, currency: "X" } }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ ...players, teamFee: { ...fee, amountCents: 30000 } }))).status).toBe(201);
  });

  it("validSeason(): leagues only; weeks 1-26, playoff weeks 0-3 and no more than the weeks, playoffs of 0, 2, 4 or 8, 1-2 games a night, up to 10 skipped dates", async () => {
    const season = { weeks: 8, playoffWeeks: 1, playoffTeams: 4, gamesPerNight: 1, skipDates: [] };
    const league = (s: Record<string, unknown>) => hosting({ kind: "league", season: { ...season, ...s } });
    expect((await call("POST", "/v1/tournaments", hosting({ season }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", league({}))).status).toBe(201);
    expect((await call("POST", "/v1/tournaments", league({ weeks: 0 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", league({ weeks: 27 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", league({ playoffWeeks: 4 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", league({ weeks: 2, playoffWeeks: 3 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", league({ weeks: 2, playoffWeeks: 2 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", league({ playoffTeams: 3 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", league({ gamesPerNight: 3 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", league({ skipDates: Array.from({ length: 11 }, (_, i) => iso(2027, 0, i + 1)) }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", league({ playoffTeams: 4, playoffWeeks: 0 }))).status).toBe(400);
  });

  it("validFormat(): a settings map, a level, 2-64 teams, roster minimum 2-30", async () => {
    const format = (f: Record<string, unknown>) => hosting({ format: { settings, level: "club", maxTeams: 8, minRoster: null, ...f } });
    expect((await call("POST", "/v1/tournaments", format({ level: "pro" }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", format({ maxTeams: 1 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", format({ maxTeams: 65 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", format({ minRoster: 1 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", format({ minRoster: 31 }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", format({ settings: { ...settings, format: "swiss" } }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", format({ extra: true }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", format({ minRoster: 5 }))).status).toBe(201);
  });

  it("names, text and choices: name 1-100, description 2000, location 200, visibility, kind, entry type, draft mode, dates", async () => {
    expect((await call("POST", "/v1/tournaments", hosting({ name: "" }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ name: "x".repeat(101) }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ description: "x".repeat(2001) }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ location: "x".repeat(201) }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ visibility: "secret" }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ kind: "camp" }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ entryType: "both" }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ draftMode: "random" }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ startsOn: "tomorrow" }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ endsOn: iso(2026, 11, 1) }))).status).toBe(400);
  });

  it("divisions: at least one, each once", async () => {
    expect((await call("POST", "/v1/tournaments", hosting({ divisions: [] }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ divisions: ["mixed", "mixed"] }))).status).toBe(400);
    expect((await call("POST", "/v1/tournaments", hosting({ divisions: ["coed"] }))).status).toBe(400);
    const res = await call("POST", "/v1/tournaments", hosting({ divisions: ["women", "mixed"] }));
    expect((store.doc(`tournaments/${res.json().id}`)?.divisions as Array<{ division: string }>).map((d) => d.division)).toEqual(["mixed", "women"]);
  });
});

describe("editing (update: manages, hostId/createdBy/createdAt kept, validHosted)", () => {
  it("only managers; a draft is hidden from everyone else", async () => {
    const { id } = await host();
    expect((await call("PATCH", `/v1/tournaments/${id}`, details(), "fan")).status).toBe(404);
    await call("PUT", `/v1/tournaments/${id}/status`, { status: "registration" });
    expect((await call("PATCH", `/v1/tournaments/${id}`, details(), "fan")).status).toBe(403);
    expect((await call("PATCH", "/v1/tournaments/ghost", details())).status).toBe(404);
  });

  it("keeps hostId, createdBy, createdAt, kind and entry type; can't take them in the body", async () => {
    const { id } = await host();
    expect((await call("PATCH", `/v1/tournaments/${id}`, { ...details(), hostId: "red" })).status).toBe(400);
    expect((await call("PATCH", `/v1/tournaments/${id}`, { ...details(), kind: "league" })).status).toBe(400);
    expect((await call("PATCH", `/v1/tournaments/${id}`, details({ name: "Fall Fling" }), "owner")).status).toBe(204);
    expect(store.doc(`tournaments/${id}`)).toMatchObject({ name: "Fall Fling", hostId: "host", createdBy: "mgr", createdAt: new Date(now), kind: "tournament" });
  });

  it("validHosted() on update too", async () => {
    const { id } = await host();
    expect((await call("PATCH", `/v1/tournaments/${id}`, details({ season: { weeks: 8, playoffWeeks: 0, playoffTeams: 0, gamesPerNight: 1, skipDates: [] } }))).status).toBe(400);
    expect((await call("PATCH", `/v1/tournaments/${id}`, details({ teamEntry: true }))).status).toBe(400);
  });

  it("opens and closes divisions; a division with teams stays; the format follows until schedules are out", async () => {
    const t = await accepted([["red", "cap"]]);
    expect((await call("PATCH", `/v1/tournaments/${t.id}`, details({ divisions: ["women"], format: { settings, level: "club", maxTeams: 12, minRoster: null } }))).status).toBe(204);
    const list = store.doc(`tournaments/${t.id}`)?.divisions as Array<{ id: string; division: string }>;
    expect(list.map((d) => d.division)).toEqual(["mixed", "women"]);
    // Unticked but locked: it stays, as it was.
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.maxTeams).toBe(8);
    expect(store.doc(`tournaments/${t.id}/divisions/${list[1].id}`)?.maxTeams).toBe(12);
    expect((await call("PATCH", `/v1/tournaments/${t.id}`, details({ divisions: ["mixed", "women"], format: { settings, level: "club", maxTeams: 12, minRoster: null } }))).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.maxTeams).toBe(12);
    const women = list[1].id;
    expect((await call("PATCH", `/v1/tournaments/${t.id}`, details({ divisions: ["mixed"] }))).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/divisions/${women}`)).toBeUndefined();
    // Publishing a schedule makes it scheduled (it isn't set by hand).
    store.put(`tournaments/${t.id}`, { ...store.doc(`tournaments/${t.id}`)!, status: "scheduled" });
    expect((await call("PATCH", `/v1/tournaments/${t.id}`, details({ format: { settings, level: "club", maxTeams: 16, minRoster: null } }))).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.maxTeams).toBe(8);
  });
});

describe("closing a division with many games", () => {
  it("deletes every game, a page at a time, then the division", async () => {
    const t = await host({ divisions: ["mixed", "women"] });
    const women = (store.doc(`tournaments/${t.id}`)?.divisions as Array<{ id: string; division: string }>).find((d) => d.division === "women")!.id;
    for (let i = 0; i < 1000; i++) store.put(`tournaments/${t.id}/divisions/${women}/games/g${String(i).padStart(4, "0")}`, { order: i });
    let biggest = 0;
    const transact = store.transact.bind(store);
    store.transact = (fn) =>
      transact((tx) => {
        let writes = 0;
        const count = <A extends unknown[]>(f: (...a: A) => void) => (...a: A) => (writes++, (biggest = Math.max(biggest, writes)), f(...a));
        return fn({ ...tx, create: count(tx.create), set: count(tx.set), update: count(tx.update), merge: count(tx.merge), delete: count(tx.delete) });
      });
    expect((await call("PATCH", `/v1/tournaments/${t.id}`, details({ divisions: ["mixed"] }))).status).toBe(204);
    expect([...store.docs.keys()].filter((k) => k.includes(`/divisions/${women}`))).toEqual([]);
    expect(biggest).toBeLessThanOrEqual(500);
  });

  it("deletes nothing when the request is refused", async () => {
    const t = await host({ divisions: ["mixed", "women"] });
    const women = (store.doc(`tournaments/${t.id}`)?.divisions as Array<{ id: string; division: string }>).find((d) => d.division === "women")!.id;
    store.put(`tournaments/${t.id}/divisions/${women}/games/g1`, { order: 1 });
    const bad = details({ divisions: ["mixed"], season: { weeks: 4, playoffTeams: 0, playoffWeeks: 0 } });
    expect((await call("PATCH", `/v1/tournaments/${t.id}`, bad)).status).toBe(400);
    expect(store.doc(`tournaments/${t.id}/divisions/${women}/games/g1`)).toBeDefined();
  });
});

describe("status and delete", () => {
  it("registration opens only within 60 days of the start (the location can come later)", async () => {
    const far = iso(2027, 1, 1);
    const { id } = await host({ startsOn: far, location: "", format: { settings: { ...settings, startsAt: far }, level: "club", maxTeams: 8, minRoster: null } });
    const r = await call("PUT", `/v1/tournaments/${id}/status`, { status: "registration" });
    expect(r.status).toBe(412);
    expect(r.json().error.message).toContain("Registration opens 60 days before the event, on Dec 3, 2026");
    expect(store.doc(`tournaments/${id}`)?.status).toBe("draft");
    // Open (no location yet), it can't be moved out of the window.
    const near = await open({ location: "" });
    const moved = await call("PATCH", `/v1/tournaments/${near.id}`, details({ startsOn: far }));
    expect(moved.status).toBe(412);
    expect(moved.json().error.message).toContain("Move it back to a draft first");
  });

  it("managers set any listed status", async () => {
    const { id } = await host();
    expect((await call("PUT", `/v1/tournaments/${id}/status`, { status: "registration" }, "fan")).status).toBe(404);
    await call("PUT", `/v1/tournaments/${id}/status`, { status: "registration" });
    expect((await call("PUT", `/v1/tournaments/${id}/status`, { status: "draft" }, "fan")).status).toBe(403);
    expect((await call("PUT", `/v1/tournaments/${id}/status`, { status: "over" })).status).toBe(400);
    expect((await call("PUT", `/v1/tournaments/${id}/status`, { status: "seeding" })).status).toBe(204);
    expect(store.doc(`tournaments/${id}`)?.status).toBe("seeding");
  });

  it("delete: managers only, with every subcollection", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games: plan(["red", "blue"]) });
    store.put(`tournaments/${t.id}/payments/red`, { paid: true });
    store.put(`tournaments/${t.id}/signups/u1`, { name: "U" });
    store.put(`tournaments/${t.id}/drafts/${t.div}`, { captainIds: [] });
    store.put(`tournaments/${t.id}/drafts/${t.div}/details/pool`, {});
    expect((await call("DELETE", `/v1/tournaments/${t.id}`, undefined, "cap")).status).toBe(403);
    expect((await call("DELETE", `/v1/tournaments/${t.id}`)).status).toBe(204);
    expect([...store.docs.keys()].filter((k) => k.startsWith(`tournaments/${t.id}`))).toEqual([]);
  });

  it("a division with accepted teams can't be removed; an empty one goes with its games and its place in the list", async () => {
    const t = await accepted([["red", "cap"]]);
    expect(code(await call("DELETE", `/v1/tournaments/${t.id}/divisions/${t.div}`))).toBe("failed_precondition");
    const b = await host({ divisions: ["mixed", "open"] });
    const open = (store.doc(`tournaments/${b.id}`)?.divisions as Array<{ id: string }>)[1].id;
    expect((await call("DELETE", `/v1/tournaments/${b.id}/divisions/${open}`, undefined, "fan")).status).toBe(404);
    expect((await call("DELETE", `/v1/tournaments/${b.id}/divisions/${open}`)).status).toBe(204);
    expect(store.doc(`tournaments/${b.id}/divisions/${open}`)).toBeUndefined();
    expect(store.doc(`tournaments/${b.id}`)?.divisions).toHaveLength(1);
  });
});

describe("authorized before anything is listed", () => {
  it("strangers and fans are refused before a query, and every chunked write is re-checked", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    const games = plan(["red", "blue"]);
    expect((await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games })).status).toBe(204);
    store.put(`tournaments/${t.id}/divisions/${t.div}/games/${games[0].id}`, {
      ...(store.doc(`tournaments/${t.id}/divisions/${t.div}/games/${games[0].id}`) as object),
      status: "reported",
      report: { scoreA: 11, scoreB: 5, byTeam: games[0].teamA },
    });
    const d = `/v1/tournaments/${t.id}/divisions/${t.div}`;
    const g = `${d}/games/${games[0].id}`;
    for (const [method, url, body, uid, status] of [
      ["POST", `${d}/reconcile`, undefined, "fan", 403],
      ["POST", `${d}/reconcile`, undefined, "stranger", 403],
      ["PATCH", `/v1/tournaments/${t.id}`, details(), "fan", 403],
      ["DELETE", d, undefined, "fan", 403],
      ["PUT", `${d}/schedule`, { games }, "fan", 403],
      ["PUT", `${g}/score`, { scoreA: 11, scoreB: 5 }, "fan", 403],
      ["POST", `${d}/seed-bracket`, undefined, "fan", 403],
      ["POST", `${g}/confirm`, { scoreA: 11, scoreB: 5 }, "fan", 403],
      // The reporting captain can't confirm their own report.
      ["POST", `${g}/confirm`, { scoreA: 11, scoreB: 5 }, games[0].teamA === "red" ? "cap" : "bcap", 403],
      ["PUT", `/v1/tournaments/${t.id}/entries/green`, { divisionId: t.div, captainIds: ["gcap"] }, "fan", 403],
    ] as const) {
      queried = [];
      const res = await call(method, url, body as object | undefined, uid);
      expect([res.status, url]).toEqual([status, url]);
      expect([queried, url]).toEqual([[], url]);
    }
  });

  it("a schedule body past the 64 KB default reaches the checks (its own bodyLimit)", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    const [g] = plan(["red", "blue"]);
    const games = Array.from({ length: 300 }, (_, i) => ({ ...g, id: `g${String(i + 1).padStart(3, "0")}`, order: i, teamA: "x".repeat(128) }));
    expect(JSON.stringify({ games }).length).toBeGreaterThan(64 * 1024);
    const res = await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games });
    expect(res.status).toBe(400);
    expect(res.json().error.message).toMatch(/doesn't match the division's teams/);
  });

  it("delete pages through subcollections bigger than one list", async () => {
    const t = await host();
    for (let i = 0; i < 2300; i++) store.put(`tournaments/${t.id}/entries/team${String(i).padStart(4, "0")}`, { status: "applied" });
    for (let i = 0; i < 500; i++) store.put(`tournaments/${t.id}/divisions/${t.div}/games/g${String(i).padStart(4, "0")}`, { order: i });
    store.put(`tournaments/${t.id}/drafts/${t.div}`, { status: "finished" });
    store.put(`tournaments/${t.id}/drafts/${t.div}/details/pool`, {});
    store.put(`tournaments/${t.id}/drafts/${t.div}/details/extra`, {});
    expect((await call("DELETE", `/v1/tournaments/${t.id}`)).status).toBe(204);
    expect([...store.docs.keys()].filter((k) => k.startsWith(`tournaments/${t.id}`))).toEqual([]);
  });
});

describe("entries (validEntry, teamApplies, teamEdits, teamWithdraws, manages)", () => {
  it("teamApplies(): teamAdmin, status applied, registration open, a team, written with the server's time", async () => {
    const t = await host();
    expect(code(await enter(t.id, t.div, "red", "cap"))).toBe("not_found");
    await call("PUT", `/v1/tournaments/${t.id}/status`, { status: "registration" });
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red`, { divisionId: t.div, captainIds: ["cap"] }, "cap2")).status).toBe(403);
    expect((await enter(t.id, t.div, "red", "cap")).status).toBe(200);
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toEqual({ teamName: "Red", divisionId: t.div, status: "applied", captainIds: ["cap"], teamId: "red", replyBy: null, roster: [], rosterSetAt: null, reason: null, updatedAt: new Date(now) });
    await call("PUT", `/v1/tournaments/${t.id}/status`, { status: "seeding" });
    expect(code(await enter(t.id, t.div, "blue", "bcap"))).toBe("failed_precondition");
    store.put("teams/group", { ...team("Group", "gl"), kind: "community" });
    await call("PUT", `/v1/tournaments/${t.id}/status`, { status: "registration" });
    expect(code(await call("PUT", `/v1/tournaments/${t.id}/entries/group`, { divisionId: t.div, captainIds: ["gl"] }, "gl"))).toBe("invalid_argument");
  });

  it("player-entry events take teams only when they reserve spots", async () => {
    const t = await open({ entryType: "players" });
    expect(code(await enter(t.id, t.div, "red", "cap"))).toBe("failed_precondition");
    const m = await open({ entryType: "players", teamEntry: true });
    store.put("teams/new", team("New", "nc"));
    expect((await enter(m.id, m.div, "new", "nc")).status).toBe(200);
  });

  it("invite only: a team enters by accepting the host's invite, straight in (seeded, its captains reporting)", async () => {
    const t = await open({ visibility: "inviteOnly" });
    expect(code(await enter(t.id, t.div, "red", "cap"))).toBe("permission_denied");
    expect((await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div }, "cap")).status).toBe(403);
    expect((await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div })).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toMatchObject({ status: "invited", captainIds: [] });
    expect(code(await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div }))).toBe("already_exists");
    const res = await enter(t.id, t.div, "red", "cap");
    expect(res.status).toBe(200);
    expect(res.json()).toEqual({ status: "accepted" });
    expect(store.doc(`tournaments/${t.id}/entries/red`)?.status).toBe("accepted");
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)).toMatchObject({ seeds: ["red"], captains: { red: ["cap"] } });
  });

  it("an invite taken up when the division is full goes on the waitlist", async () => {
    const t = await open({ visibility: "inviteOnly", format: { settings, level: "club", maxTeams: 2, minRoster: null } });
    for (const team of ["red", "blue", "green"]) await call("POST", `/v1/tournaments/${t.id}/entries/${team}/invite`, { divisionId: t.div });
    expect((await enter(t.id, t.div, "red", "cap")).json()).toEqual({ status: "accepted" });
    expect((await enter(t.id, t.div, "blue", "bcap")).json()).toEqual({ status: "accepted" });
    expect((await enter(t.id, t.div, "green", "gcap")).json()).toEqual({ status: "waitlisted" });
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.seeds).toEqual(["red", "blue"]);
  });

  it("an application still waits for the host", async () => {
    const t = await open();
    expect((await enter(t.id, t.div, "red", "cap")).json()).toEqual({ status: "applied" });
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.seeds).toEqual([]);
  });

  it("declining an invite: the team withdraws saying why; the reason goes if it enters again", async () => {
    const t = await open({ visibility: "inviteOnly" });
    await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div });
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "withdrawn", reason: "declined" }, "cap")).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toMatchObject({ status: "withdrawn", reason: "declined" });
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "withdrawn", reason: "bored" }, "cap")).status).toBe(400);
    await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div });
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toMatchObject({ status: "invited", reason: null });
  });

  it("validEntry(): 1-4 captains, every one on the team; a real division", async () => {
    const t = await open();
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red`, { divisionId: t.div, captainIds: [] }, "cap")).status).toBe(400);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red`, { divisionId: t.div, captainIds: ["a", "b", "c", "d", "e"] }, "cap")).status).toBe(400);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red`, { divisionId: t.div, captainIds: ["bcap"] }, "cap")).status).toBe(400);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red`, { divisionId: "nope", captainIds: ["cap"] }, "cap")).status).toBe(404);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red`, { divisionId: t.div, captainIds: ["cap", "cap2"] }, "cap")).status).toBe(200);
  });

  it("entering doesn't need the roster yet: it's named for the event later", async () => {
    const t = await open({ format: { settings, level: "club", maxTeams: 8, minRoster: 10 } });
    expect((await enter(t.id, t.div, "red", "cap")).status).toBe(200);
  });

  it("the event roster: the team's admins or captains, players from its roster, at least the minimum (any where teams reserve spots), until play starts", async () => {
    const t = await open({ format: { settings, level: "club", maxTeams: 8, minRoster: 3 } });
    const url = `/v1/tournaments/${t.id}/entries/red/roster`;
    expect((await call("PUT", url, { playerIds: ["p0", "p1", "p2"] }, "cap"))).toMatchObject({ status: 404 });
    await enter(t.id, t.div, "red", "cap");
    // Not a stranger, another team's captain or a player.
    expect((await call("PUT", url, { playerIds: ["p0", "p1", "p2"] }, "bcap")).status).toBe(403);
    expect((await call("PUT", url, { playerIds: ["p0", "p1", "p2"] }, "fan")).status).toBe(403);
    // Too few, someone not on the roster, twice the same.
    expect(code(await call("PUT", url, { playerIds: ["p0", "p1"] }, "cap"))).toBe("invalid_argument");
    expect(code(await call("PUT", url, { playerIds: ["p0", "p1", "ghost"] }, "cap"))).toBe("invalid_argument");
    expect((await call("PUT", url, { playerIds: ["p0", "p0", "p1"] }, "cap")).status).toBe(400);
    expect((await call("PUT", url, { playerIds: ["p0", "p1", "p2"] }, "cap")).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toMatchObject({ roster: ["p0", "p1", "p2"], rosterSetAt: new Date(now) });
    // A captain named for the event (not an admin of the team) can change it too.
    await call("PUT", `/v1/tournaments/${t.id}/entries/red`, { divisionId: t.div, captainIds: ["cap2"] }, "cap");
    expect((await call("PUT", url, { playerIds: ["p3", "p4", "p5"] }, "cap2")).status).toBe(204);
    // The roster stays through the host's decision.
    await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "accepted" });
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toMatchObject({ status: "accepted", roster: ["p3", "p4", "p5"] });
    // Locked once play starts.
    store.put(`tournaments/${t.id}`, { ...store.doc(`tournaments/${t.id}`)!, status: "live" });
    expect(code(await call("PUT", url, { playerIds: ["p0", "p1", "p2"] }, "cap"))).toBe("failed_precondition");
    // Teams reserving spots fill theirs as they go.
    const m = await open({ entryType: "players", teamEntry: true });
    await enter(m.id, m.div, "blue", "bcap");
    expect((await call("PUT", `/v1/tournaments/${m.id}/entries/blue/roster`, { playerIds: ["p0"] }, "bcap")).status).toBe(204);
  });

  it("a league division takes teams of its division and level", async () => {
    const season = { weeks: 8, playoffWeeks: 0, playoffTeams: 0, gamesPerNight: 1, skipDates: [] };
    const t = await open({ kind: "league", season, format: { settings, level: "college", maxTeams: 8, minRoster: null } });
    expect(code(await enter(t.id, t.div, "red", "cap"))).toBe("failed_precondition");
    store.put("teams/red", { ...store.doc("teams/red"), level: "college" });
    expect((await enter(t.id, t.div, "red", "cap"))?.status).toBe(200);
  });

  it("teamEdits(): captains change, status and division stay", async () => {
    const t = await accepted([["red", "cap"]]);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red`, { divisionId: t.div, captainIds: ["cap2"] }, "cap")).status).toBe(200);
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toMatchObject({ status: "accepted", captainIds: ["cap2"] });
    expect(code(await call("PUT", `/v1/tournaments/${t.id}/entries/red`, { divisionId: "other", captainIds: ["cap"] }, "cap"))).toBe("not_found");
  });

  it("a declined team doesn't apply again on its own", async () => {
    const t = await open();
    await enter(t.id, t.div, "red", "cap");
    await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "declined" });
    expect(code(await enter(t.id, t.div, "red", "cap"))).toBe("failed_precondition");
  });

  it("teamWithdraws(): the team's admins withdraw, only that", async () => {
    const t = await open();
    await enter(t.id, t.div, "red", "cap");
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "accepted" }, "cap")).status).toBe(403);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "withdrawn" }, "cap2")).status).toBe(403);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "withdrawn" }, "cap")).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toMatchObject({ status: "withdrawn", captainIds: ["cap"], teamName: "Red" });
    expect((await enter(t.id, t.div, "red", "cap")).status).toBe(200);
  });

  it("the host accepts (seeded last, captains report), unless the division is full; anything else unseeds", async () => {
    const t = await open({ format: { settings, level: "club", maxTeams: 2, minRoster: null } });
    for (const [id, c] of [["red", "cap"], ["blue", "bcap"], ["green", "gcap"]]) await enter(t.id, t.div, id, c);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "accepted" })).status).toBe(204);
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/blue/status`, { status: "accepted" })).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)).toMatchObject({ seeds: ["red", "blue"], captains: { red: ["cap"], blue: ["bcap"] } });
    expect(code(await call("PUT", `/v1/tournaments/${t.id}/entries/green/status`, { status: "accepted" }))).toBe("failed_precondition");
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "waitlisted" })).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)).toMatchObject({ seeds: ["blue"], captains: { blue: ["bcap"] } });
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/ghost/status`, { status: "accepted" })).status).toBe(404);
  });

  it("seeds: the host reorders the accepted teams, not adds or drops them, until the schedule is out", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    const url = `/v1/tournaments/${t.id}/divisions/${t.div}/seeds`;
    expect((await call("PUT", url, { seeds: ["blue", "red"] }, "cap")).status).toBe(403);
    expect(code(await call("PUT", url, { seeds: ["blue", "green"] }))).toBe("failed_precondition");
    expect((await call("PUT", url, { seeds: ["blue", "red"] })).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.seeds).toEqual(["blue", "red"]);
    await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games: plan(["blue", "red"]) });
    expect(code(await call("PUT", url, { seeds: ["red", "blue"] }))).toBe("failed_precondition");
  });
});

describe("invites: reply-by time, expiry, the team's list and declining", () => {
  const day = 24 * 60 * 60 * 1000;
  // The event starts 2026-12-05; `now` is 2026-11-14 12:00 UTC.
  it("an invite carries the event's reply-by time and the team id", async () => {
    const t = await open({ visibility: "inviteOnly", inviteReplyDays: 14 });
    expect(store.doc(`tournaments/${t.id}`)?.inviteReplyDays).toBe(14);
    expect((await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div })).status).toBe(204);
    const entry = store.doc(`tournaments/${t.id}/entries/red`)!;
    expect(entry).toMatchObject({ status: "invited", teamId: "red" });
    expect((entry.replyBy as Date).toISOString()).toBe(new Date(Date.UTC(2026, 11, 5) - 14 * day).toISOString());
  });

  it("no deadline without inviteReplyDays; only the choices are taken", async () => {
    const t = await open({ visibility: "inviteOnly" });
    await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div });
    expect(store.doc(`tournaments/${t.id}/entries/red`)?.replyBy).toBeNull();
    expect(code(await call("POST", "/v1/tournaments", hosting({ inviteReplyDays: 10 })))).toBe("invalid_argument");
  });

  it("past its reply-by time an invite can't be accepted; the host can invite again", async () => {
    const t = await open({ visibility: "inviteOnly", inviteReplyDays: 14 });
    await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div });
    store.put(`tournaments/${t.id}/entries/red`, { ...store.doc(`tournaments/${t.id}/entries/red`)!, replyBy: new Date(now - day) });
    const late = await enter(t.id, t.div, "red", "cap");
    expect(code(late)).toBe("failed_precondition");
    expect(late.json().error.message).toMatch(/expired/);
    expect((await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div })).status).toBe(204);
    expect((await enter(t.id, t.div, "red", "cap")).status).toBe(200);
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toMatchObject({ status: "accepted", replyBy: null });
  });

  it("a late invite still gets two days to answer", async () => {
    const soon = new Date(now + 5 * day).toISOString();
    const t = await open({ visibility: "inviteOnly", inviteReplyDays: 14, startsOn: soon, format: { settings: { ...settings, startsAt: soon }, level: "club", maxTeams: 8, minRoster: null } });
    await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div });
    expect((store.doc(`tournaments/${t.id}/entries/red`)!.replyBy as Date).getTime()).toBe(now + 2 * day);
  });

  // The team's record of the entry, as the entrySchedule trigger keeps it.
  const record = (id: string, status = "invited") => store.put(`teams/red/tournamentEntries/${id}`, { name: "Spring Fling", status });

  it("a team's admins list its invites, and decline one", async () => {
    const t = await open({ visibility: "inviteOnly", inviteReplyDays: 14 });
    await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div });
    record(t.id);
    const res = await call("GET", "/v1/teams/red/tournament-invites", undefined, "cap");
    expect(res.status).toBe(200);
    expect(res.json().invites).toEqual([
      expect.objectContaining({ tournamentId: t.id, name: "Spring Fling", hostName: "Host Club", divisionId: t.div, divisionLabel: expect.any(String), expired: false }),
    ]);
    // Not for the team's players, nor other teams' admins.
    expect((await call("GET", "/v1/teams/red/tournament-invites", undefined, "cap2")).status).toBe(403);
    expect((await call("GET", "/v1/teams/red/tournament-invites", undefined, "bcap")).status).toBe(403);
    // Declining: the team withdraws.
    expect((await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "withdrawn" }, "cap")).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/entries/red`)).toMatchObject({ status: "withdrawn", replyBy: null });
    // Before the trigger catches up, the entry itself has the last word.
    expect((await call("GET", "/v1/teams/red/tournament-invites", undefined, "cap")).json().invites).toEqual([]);
  });

  it("an expired invite is listed as expired", async () => {
    const t = await open({ visibility: "inviteOnly", inviteReplyDays: 14 });
    await call("POST", `/v1/tournaments/${t.id}/entries/red/invite`, { divisionId: t.div });
    record(t.id);
    store.put(`tournaments/${t.id}/entries/red`, { ...store.doc(`tournaments/${t.id}/entries/red`)!, replyBy: new Date(now - day) });
    expect((await call("GET", "/v1/teams/red/tournament-invites", undefined, "cap")).json().invites[0]).toMatchObject({ expired: true });
  });
});

describe("schedule (games create: manages, validGame)", () => {
  it("publishes the generated games: managers only, at least two teams, teams from the seeds", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    const url = `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`;
    expect((await call("PUT", url, { games: plan(["red", "blue"]) }, "cap")).status).toBe(403);
    expect((await call("PUT", url, { games: plan(["red", "green"]) })).status).toBe(400);
    expect((await call("PUT", url, { games: plan(["red", "blue"]) })).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}/games/g001`)).toMatchObject({
      teamA: "red", teamB: "blue", status: "scheduled", scoreA: null, scoreB: null, report: null, ifNeeded: false,
    });
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}/games/g001`)?.startsAt).toBeInstanceOf(Date);
    expect(store.doc(`tournaments/${t.id}`)?.status).toBe("scheduled");
    const one = await accepted([["green", "gcap"]]);
    expect(code(await call("PUT", `/v1/tournaments/${one.id}/divisions/${one.div}/schedule`, { games: plan(["green", "x"]) }))).toBe("failed_precondition");
  });

  it("validGame(): stages, statuses, a label up to 60, places 1-64, ids once, in order", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    const url = `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`;
    const [g] = plan(["red", "blue"]);
    expect((await call("PUT", url, { games: [{ ...g, stage: "semis" }] })).status).toBe(400);
    expect((await call("PUT", url, { games: [{ ...g, label: "x".repeat(61) }] })).status).toBe(400);
    expect((await call("PUT", url, { games: [{ ...g, place: 65 }] })).status).toBe(400);
    expect((await call("PUT", url, { games: [{ ...g, status: "done" }] })).status).toBe(400);
    expect((await call("PUT", url, { games: [g, g] })).status).toBe(400);
    expect((await call("PUT", url, { games: [{ ...g, order: 3 }] })).status).toBe(400);
    expect((await call("PUT", url, { games: [{ ...g, sourceA: { type: "winner", game: "g099" } }] })).status).toBe(400);
  });

  it("republishing replaces the games and clears the division's results", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"], ["green", "gcap"]]);
    const url = `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`;
    await call("PUT", url, { games: plan(["red", "blue", "green"]) });
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}/games/g003`)).toBeDefined();
    store.put(`tournaments/${t.id}/divisions/${t.div}`, { ...store.doc(`tournaments/${t.id}/divisions/${t.div}`), placements: ["red"] });
    await call("PUT", url, { games: plan(["red", "blue"]) });
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}/games/g003`)).toBeUndefined();
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.placements).toEqual([]);
  });
});

describe("scores (report, confirm, advance, managers)", () => {
  async function bracket() {
    const t = await accepted([["red", "cap"], ["blue", "bcap"], ["green", "gcap"]]);
    await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games: plan(["red", "blue", "green"], "singleElim") });
    // 3 teams: red has a bye; g001 is blue v green, g002 red v its winner.
    const g = (id: string) => store.doc(`tournaments/${t.id}/divisions/${t.div}/games/${id}`) as Record<string, unknown>;
    return { ...t, g, url: (id: string, what: string) => `/v1/tournaments/${t.id}/divisions/${t.div}/games/${id}/${what}` };
  }

  it("report(): a captain of either team, both teams known, not final, scores 0-99 and no tie", async () => {
    const b = await bracket();
    expect(b.g("g001")).toMatchObject({ teamA: "blue", teamB: "green" });
    expect((await call("POST", b.url("g001", "report"), { scoreA: 15, scoreB: 10 }, "cap")).status).toBe(403);
    expect((await call("POST", b.url("g001", "report"), { scoreA: 15, scoreB: 15 }, "bcap")).status).toBe(400);
    expect((await call("POST", b.url("g001", "report"), { scoreA: 100, scoreB: 1 }, "bcap")).status).toBe(400);
    expect(code(await call("POST", b.url("g002", "report"), { scoreA: 15, scoreB: 1 }, "cap"))).toBe("failed_precondition");
    expect((await call("POST", b.url("g001", "report"), { scoreA: 15, scoreB: 10 }, "bcap")).status).toBe(204);
    expect(b.g("g001")).toMatchObject({ status: "reported", report: { scoreA: 15, scoreB: 10, byTeam: "blue" } });
  });

  it("confirm(): only the other team's captain; the result moves the winner on", async () => {
    const b = await bracket();
    const seen = { scoreA: 15, scoreB: 10 };
    expect(code(await call("POST", b.url("g001", "confirm"), seen, "gcap"))).toBe("failed_precondition");
    await call("POST", b.url("g001", "report"), { scoreA: 15, scoreB: 10 }, "bcap");
    expect((await call("POST", b.url("g001", "confirm"), seen, "bcap")).status).toBe(403);
    expect((await call("POST", b.url("g001", "confirm"), seen, "cap")).status).toBe(403);
    // The score being confirmed is required and must be the one reported.
    expect((await call("POST", b.url("g001", "confirm"), undefined, "gcap")).status).toBe(400);
    expect(code(await call("POST", b.url("g001", "confirm"), { scoreA: 15, scoreB: 9 }, "gcap"))).toBe("failed_precondition");
    expect(code(await call("POST", b.url("g001", "confirm"), { scoreA: 14, scoreB: 10 }, "gcap"))).toBe("failed_precondition");
    expect(b.g("g001")).toMatchObject({ status: "reported" });
    expect((await call("POST", b.url("g001", "confirm"), seen, "gcap")).status).toBe(204);
    expect(b.g("g001")).toMatchObject({ status: "done", scoreA: 15, scoreB: 10, report: null });
    expect(b.g("g002")).toMatchObject({ teamA: "red", teamB: "blue" });
    expect(code(await call("POST", b.url("g001", "report"), { scoreA: 1, scoreB: 15 }, "gcap"))).toBe("failed_precondition");
  });

  it("the host sets or corrects a final score, until later games depend on it", async () => {
    const b = await bracket();
    expect((await call("PUT", b.url("g001", "score"), { scoreA: 15, scoreB: 10 }, "bcap")).status).toBe(403);
    expect((await call("PUT", b.url("g002", "score"), { scoreA: 15, scoreB: 10 })).status).toBe(412);
    expect((await call("PUT", b.url("g001", "score"), { scoreA: 15, scoreB: 10 })).status).toBe(204);
    expect(b.g("g002")?.teamB).toBe("blue");
    expect((await call("PUT", b.url("g001", "score"), { scoreA: 10, scoreB: 15 })).status).toBe(204);
    expect(b.g("g002")?.teamB).toBe("green");
    await call("PUT", b.url("g002", "score"), { scoreA: 15, scoreB: 3 });
    expect(code(await call("PUT", b.url("g001", "score"), { scoreA: 15, scoreB: 10 }))).toBe("failed_precondition");
  });

  it("the host seeds a bracket from the pools once they're done", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"], ["green", "gcap"]]);
    store.put("teams/gold", team("Gold", "ycap"));
    for (let i = 0; i < 7; i++) store.put(`teams/gold/roster/p${i}`, {});
    await enter(t.id, t.div, "gold", "ycap");
    await call("PUT", `/v1/tournaments/${t.id}/entries/gold/status`, { status: "accepted" });
    const seeds = ["red", "blue", "green", "gold"];
    const games = plan(seeds, "poolsSingleElim");
    await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games });
    const url = `/v1/tournaments/${t.id}/divisions/${t.div}/seed-bracket`;
    expect(code(await call("POST", url))).toBe("failed_precondition");
    for (const g of games.filter((x) => x.stage === "pool")) {
      await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/games/${g.id}/score`, { scoreA: 15, scoreB: 10 });
    }
    expect((await call("POST", url, undefined, "cap")).status).toBe(403);
    expect((await call("POST", url)).status).toBe(204);
    const final = games.find((g) => g.stage === "winners") as { id: string };
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}/games/${final.id}`)?.teamA).not.toBeNull();
  });
});

describe("live running scores (setLive, clearLive)", () => {
  async function live() {
    const t = await accepted([["red", "cap"], ["blue", "bcap"], ["green", "gcap"]]);
    await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games: plan(["red", "blue", "green"], "singleElim") });
    expect((await call("PUT", `/v1/tournaments/${t.id}/status`, { status: "scheduled" })).status).toBe(204);
    const path = (id: string) => `tournaments/${t.id}/divisions/${t.div}/games/${id}`;
    const g = (id: string) => store.doc(path(id)) as Record<string, unknown>;
    // Played today: g001 (blue v green) starts now.
    for (const id of ["g001", "g002"]) store.put(path(id), { ...g(id), startsAt: new Date(now) });
    const url = (id: string) => `/v1/tournaments/${t.id}/divisions/${t.div}/games/${id}/live`;
    return { ...t, g, path, url };
  }

  it("either team's captain or a host manager; not other captains, members or outsiders", async () => {
    const b = await live();
    for (const uid of ["cap", "fan", "stranger"]) {
      expect((await call("POST", b.url("g001"), { scoreA: 1, scoreB: 0 }, uid)).status).toBe(403);
    }
    expect(b.g("g001").live).toBeUndefined();
    expect((await call("POST", b.url("g001"), { scoreA: 0, scoreB: 0 }, "bcap")).status).toBe(204);
    expect(b.g("g001").live).toEqual({ scoreA: 0, scoreB: 0, startedAt: new Date(now), updatedAt: new Date(now), by: "bcap" });
    expect((await call("POST", b.url("g001"), { scoreA: 1, scoreB: 0 }, "gcap")).status).toBe(204);
    expect((await call("POST", b.url("g001"), { scoreA: 2, scoreB: 0 }, "mgr")).status).toBe(204);
    expect(b.g("g001").live).toMatchObject({ scoreA: 2, scoreB: 0, by: "mgr" });
  });

  it("is never the final: the game stays scheduled, nothing moves on, the final is still reported and confirmed", async () => {
    const b = await live();
    await call("POST", b.url("g001"), { scoreA: 7, scoreB: 5 }, "bcap");
    expect(b.g("g001")).toMatchObject({ status: "scheduled", scoreA: null, scoreB: null, report: null });
    expect(b.g("g002").teamB).toBeNull();
    const game = `/v1/tournaments/${b.id}/divisions/${b.div}/games/g001`;
    expect((await call("POST", `${game}/report`, { scoreA: 15, scoreB: 10 }, "bcap")).status).toBe(204);
    expect((await call("POST", `${game}/confirm`, { scoreA: 15, scoreB: 10 }, "gcap")).status).toBe(204);
    expect(b.g("g001")).toMatchObject({ status: "done", scoreA: 15, scoreB: 10 });
    expect(b.g("g002").teamB).toBe("blue");
  });

  it("scores are whole numbers 0-99 (ties fine); only the two scores", async () => {
    const b = await live();
    for (const body of [{ scoreA: -1, scoreB: 0 }, { scoreA: 100, scoreB: 0 }, { scoreA: 1.5, scoreB: 0 }, { scoreA: 1 }, { scoreA: 1, scoreB: 1, by: "x" }]) {
      expect((await call("POST", b.url("g001"), body, "bcap")).status).toBe(400);
    }
    expect((await call("POST", b.url("g001"), { scoreA: 99, scoreB: 99 }, "bcap")).status).toBe(204);
  });

  it("only scheduled games with both teams, on the day, in an event being played", async () => {
    const b = await live();
    // g002 waits on g001's winner.
    expect(code(await call("POST", b.url("g002"), { scoreA: 0, scoreB: 0 }, "cap"))).toBe("failed_precondition");
    expect((await call("POST", b.url("nope"), { scoreA: 0, scoreB: 0 }, "bcap")).status).toBe(404);
    // Too early (more than 2 hours before) and too late (a day after).
    store.put(b.path("g001"), { ...b.g("g001"), startsAt: new Date(now + 3 * 3600_000) });
    expect(code(await call("POST", b.url("g001"), { scoreA: 0, scoreB: 0 }, "bcap"))).toBe("failed_precondition");
    store.put(b.path("g001"), { ...b.g("g001"), startsAt: new Date(now - 25 * 3600_000) });
    expect(code(await call("POST", b.url("g001"), { scoreA: 0, scoreB: 0 }, "bcap"))).toBe("failed_precondition");
    store.put(b.path("g001"), { ...b.g("g001"), startsAt: new Date(now - 3600_000) });
    expect((await call("POST", b.url("g001"), { scoreA: 0, scoreB: 0 }, "bcap")).status).toBe(204);
    // Reported or final: no more running score.
    store.put(b.path("g001"), { ...b.g("g001"), status: "reported", report: { scoreA: 15, scoreB: 3, byTeam: "blue" } });
    expect(code(await call("POST", b.url("g001"), { scoreA: 1, scoreB: 0 }, "bcap"))).toBe("failed_precondition");
    store.put(b.path("g001"), { ...b.g("g001"), status: "done", scoreA: 15, scoreB: 3, report: null });
    expect(code(await call("POST", b.url("g001"), { scoreA: 1, scoreB: 0 }, "bcap"))).toBe("failed_precondition");
    // A finished event.
    store.put(b.path("g001"), { ...b.g("g001"), status: "scheduled", scoreA: null, scoreB: null });
    store.put(`tournaments/${b.id}`, { ...store.doc(`tournaments/${b.id}`), status: "finished" });
    expect(code(await call("POST", b.url("g001"), { scoreA: 1, scoreB: 0 }, "bcap"))).toBe("failed_precondition");
  });

  it("the first live game makes a scheduled event live; startedAt is kept", async () => {
    const b = await live();
    expect(store.doc(`tournaments/${b.id}`)?.status).toBe("scheduled");
    await call("POST", b.url("g001"), { scoreA: 0, scoreB: 0 }, "bcap");
    expect(store.doc(`tournaments/${b.id}`)?.status).toBe("live");
    const started = b.g("g001").live as Record<string, unknown>;
    store.put(b.path("g001"), { ...b.g("g001"), live: { ...started, startedAt: new Date(now - 600_000) } });
    await call("POST", b.url("g001"), { scoreA: 1, scoreB: 0 }, "bcap");
    expect(b.g("g001").live).toMatchObject({ scoreA: 1, startedAt: new Date(now - 600_000), updatedAt: new Date(now) });
  });

  it("DELETE takes it off, for the same people", async () => {
    const b = await live();
    await call("POST", b.url("g001"), { scoreA: 3, scoreB: 2 }, "bcap");
    expect((await call("DELETE", b.url("g001"), undefined, "cap")).status).toBe(403);
    expect((await call("DELETE", b.url("g001"), undefined, "gcap")).status).toBe(204);
    expect(b.g("g001").live).toBeUndefined();
    expect((await call("DELETE", b.url("g001"), undefined, "mgr")).status).toBe(204);
  });

  it("a draft event is hidden from captains", async () => {
    const b = await live();
    store.put(`tournaments/${b.id}`, { ...store.doc(`tournaments/${b.id}`), status: "draft" });
    expect((await call("POST", b.url("g001"), { scoreA: 0, scoreB: 0 }, "bcap")).status).toBe(404);
  });
});

describe("the host's view keeps things in step (reconcile)", () => {
  it("goes live with the first result, records places when the division is done, then final", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games: plan(["red", "blue"]) });
    const url = `/v1/tournaments/${t.id}/divisions/${t.div}/reconcile`;
    expect((await call("POST", url, undefined, "cap")).status).toBe(403);
    expect((await call("POST", url)).json().changed).toEqual([]);
    await call("POST", `/v1/tournaments/${t.id}/divisions/${t.div}/games/g001/report`, { scoreA: 15, scoreB: 9 }, "cap");
    await call("POST", `/v1/tournaments/${t.id}/divisions/${t.div}/games/g001/confirm`, { scoreA: 15, scoreB: 9 }, "bcap");
    // Done by the server with the confirmed final: nothing left for the host's look.
    expect((await call("POST", url)).json().changed).toEqual([]);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.placements).toEqual(["red", "blue"]);
    expect(store.doc(`tournaments/${t.id}`)?.status).toBe("finished");
  });

  it("reads only what it may change: no transaction when nothing changes; a fill re-reads just its games", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"], ["green", "gcap"]]);
    await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games: plan(["red", "blue", "green"], "singleElim") });
    const games = `tournaments/${t.id}/divisions/${t.div}/games`;
    // A game the fill doesn't touch, and another division's entry.
    store.put(`${games}/x900`, { order: 900, stage: "consolation", teamA: "red", teamB: "green", status: "scheduled" });
    store.put(`tournaments/${t.id}/entries/elsewhere`, { status: "accepted", divisionId: "other", captainIds: ["z"] });
    const reads: string[] = [];
    let txs = 0;
    const transact = store.transact.bind(store);
    store.transact = (fn) =>
      transact((tx) => {
        txs++;
        return fn({ ...tx, get: (path: string) => (reads.push(path), tx.get(path)) });
      });
    const url = `/v1/tournaments/${t.id}/divisions/${t.div}/reconcile`;
    expect((await call("POST", url)).json().changed).toEqual([]);
    expect(txs).toBe(0);
    // g001's result landed but g002 wasn't filled (blue v green, the winner meets red).
    store.put(`${games}/g001`, { ...(store.doc(`${games}/g001`) as object), status: "done", scoreA: 15, scoreB: 7 });
    expect((await call("POST", url)).json().changed).toEqual(["fills", "live"]);
    expect(store.doc(`${games}/g002`)).toMatchObject({ teamA: "red", teamB: "blue" });
    expect(txs).toBe(1);
    expect(reads.filter((r) => r.startsWith(games)).sort()).toEqual([`${games}/g001`, `${games}/g002`]);
    expect(reads).not.toContain(`tournaments/${t.id}/entries/elsewhere`);
  });

  it("drops a seed whose entry moved to another division and withdrew", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    store.put(`tournaments/${t.id}/entries/red`, { ...(store.doc(`tournaments/${t.id}/entries/red`) as object), divisionId: "elsewhere", status: "withdrawn" });
    const res = await call("POST", `/v1/tournaments/${t.id}/divisions/${t.div}/reconcile`);
    expect(res.json().changed).toEqual(["withdrawn"]);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)).toMatchObject({ seeds: ["blue"] });
  });

  it("drops withdrawn teams from unpublished seeds and copies captains from entries", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    await call("PUT", `/v1/tournaments/${t.id}/entries/red/status`, { status: "withdrawn" }, "cap");
    // The app changing captains straight in Firestore (through the API the division follows at once).
    store.put(`tournaments/${t.id}/entries/blue`, { ...store.doc(`tournaments/${t.id}/entries/blue`)!, captainIds: ["bcap2"] });
    const res = await call("POST", `/v1/tournaments/${t.id}/divisions/${t.div}/reconcile`);
    expect(res.json().changed).toEqual(["withdrawn", "captains"]);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)).toMatchObject({ seeds: ["blue"], captains: { blue: ["bcap2"] } });
  });
});

describe("the organizer's run sheet: status moves, confirmed seeds, publishing every division", () => {
  it("status moves one step at a time by hand; scheduled only by publishing", async () => {
    const t = await host();
    const set = (status: string) => call("PUT", `/v1/tournaments/${t.id}/status`, { status });
    expect(code(await set("seeding"))).toBe("failed_precondition");
    expect((await set("registration")).status).toBe(204);
    expect((await set("seeding")).status).toBe(204);
    expect((await set("registration")).status).toBe(204);
    expect(code(await set("scheduled"))).toBe("failed_precondition");
    expect(code(await set("finished"))).toBe("failed_precondition");
    expect((await set("draft")).status).toBe(204);
  });

  it("confirming seeds stamps them; a change unconfirms them, and so does a newly accepted team", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    const url = `/v1/tournaments/${t.id}/divisions/${t.div}/seeds`;
    const division = () => store.doc(`tournaments/${t.id}/divisions/${t.div}`)!;
    expect((await call("PUT", url, { seeds: ["blue", "red"], confirm: true })).status).toBe(204);
    expect(division()).toMatchObject({ seeds: ["blue", "red"], seedsConfirmedAt: new Date(now) });
    // Saving the same order keeps the confirmation; a new order drops it.
    expect((await call("PUT", url, { seeds: ["blue", "red"] })).status).toBe(204);
    expect(division().seedsConfirmedAt).toEqual(new Date(now));
    expect((await call("PUT", url, { seeds: ["red", "blue"] })).status).toBe(204);
    expect(division().seedsConfirmedAt).toBeNull();
    await call("PUT", url, { seeds: ["red", "blue"], confirm: true });
    await enter(t.id, t.div, "green", "gcap");
    await call("PUT", `/v1/tournaments/${t.id}/entries/green/status`, { status: "accepted" });
    expect(division()).toMatchObject({ seeds: ["red", "blue", "green"], seedsConfirmedAt: null });
  });

  it("one team isn't enough to confirm", async () => {
    const t = await accepted([["red", "cap"]]);
    expect(code(await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/seeds`, { seeds: ["red"], confirm: true }))).toBe("failed_precondition");
  });

  it("publishes every division at once, only with confirmed seeds, checking them all before writing any", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"]]);
    const url = `/v1/tournaments/${t.id}/schedule`;
    const body = (games = plan(["red", "blue"])) => ({ divisions: [{ divisionId: t.div, games }] });
    expect(code(await call("PUT", url, body()))).toBe("failed_precondition");
    await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/seeds`, { seeds: ["red", "blue"], confirm: true });
    expect((await call("PUT", url, body(), "cap")).status).toBe(403);
    expect(code(await call("PUT", url, body(plan(["red", "green"]))))).toBe("invalid_argument");
    expect(Object.keys(Object.fromEntries(store.docs)).some((k) => k.includes("/games/"))).toBe(false);
    expect(code(await call("PUT", url, { divisions: [{ divisionId: t.div, games: plan(["red", "blue"]) }, { divisionId: t.div, games: plan(["red", "blue"]) }] }))).toBe("invalid_argument");
    expect((await call("PUT", url, body())).status).toBe(204);
    expect(store.doc(`tournaments/${t.id}`)?.status).toBe("scheduled");
    expect([...store.docs.keys()].filter((k) => k.startsWith(`tournaments/${t.id}/divisions/${t.div}/games/`))).toHaveLength(1);
  });
});

describe("deleting a tournament deletes its chats", () => {
  it("the conversations behind its chats go, with their messages; other conversations stay", async () => {
    const t = await accepted([["red", "cap"]]);
    store.put(`tournaments/${t.id}/chats/captains`, { conversationId: "g-cap1", kind: "captains" });
    store.put(`tournaments/${t.id}/chats/team_red`, { conversationId: "g-red1", kind: "team", teamId: "red" });
    store.put("conversations/g-cap1", { kind: "tournament", tournamentId: t.id, participants: ["mgr", "cap"] });
    store.put("conversations/g-cap1/messages/m1", { text: "hi" });
    store.put("conversations/g-red1", { kind: "tournament", tournamentId: t.id, participants: ["mgr", "cap"] });
    store.put("conversations/g-red1/typing/cap", { at: new Date(now) });
    // A pointer at someone else's conversation doesn't delete it.
    store.put(`tournaments/${t.id}/chats/team_blue`, { conversationId: "g-other", kind: "team", teamId: "blue" });
    store.put("conversations/g-other", { kind: "group", participants: ["x"] });
    expect((await call("DELETE", `/v1/tournaments/${t.id}`, undefined, "cap")).status).toBe(403);
    expect(store.doc("conversations/g-cap1")).toBeDefined();
    expect((await call("DELETE", `/v1/tournaments/${t.id}`)).status).toBe(204);
    // The chat pointers stay for the tournamentDeleted function (it also deletes attachments).
    for (const gone of ["conversations/g-cap1", "conversations/g-cap1/messages/m1", "conversations/g-red1", "conversations/g-red1/typing/cap", `tournaments/${t.id}`]) {
      expect(store.doc(gone)).toBeUndefined();
    }
    expect(store.doc("conversations/g-other")).toBeDefined();
  });
});

describe("the tournament director and the entry deadline", () => {
  it("a director by name with optional contact details, or a member by uid", async () => {
    const director = { uid: null, name: "Dana Director", email: "dana@example.com", phone: "+1 (555) 010-0000" };
    const { id } = await host({ director });
    expect(store.doc(`tournaments/${id}`)?.director).toEqual(director);
    expect(code(await call("POST", "/v1/tournaments", hosting({ director: { name: "" } })))).toBe("invalid_argument");
    expect(code(await call("POST", "/v1/tournaments", hosting({ director: { name: "D", email: "nope" } })))).toBe("invalid_argument");
    expect(code(await call("POST", "/v1/tournaments", hosting({ director: { name: "D", phone: "call me" } })))).toBe("invalid_argument");
    expect(code(await call("POST", "/v1/tournaments", hosting({ director: { uid: "ghost", name: "Ghost" } })))).toBe("invalid_argument");
    store.put("users/dana", { name: "Dana" });
    expect((await call("POST", "/v1/tournaments", hosting({ director: { uid: "dana", name: "Dana" } }))).status).toBe(201);
  });

  it("the deadline is before the start, and the fees are due then", async () => {
    const fee = { amountCents: 25000, currency: "USD", instructions: "", dueAt: null, payerCoversFees: false };
    const deadline = iso(2026, 11, 1);
    const { id } = await host({ bidFee: fee, entryDeadline: deadline });
    const t = store.doc(`tournaments/${id}`)!;
    expect((t.entryDeadline as Date).toISOString()).toBe(deadline);
    expect(((t.bidFee as { dueAt: Date }).dueAt).toISOString()).toBe(deadline);
    expect(code(await call("POST", "/v1/tournaments", hosting({ entryDeadline: iso(2026, 11, 6) })))).toBe("invalid_argument");
  });
});

describe("finishing without the host on the page", () => {
  it("the last confirmed final records places and makes the event final; an earlier one only makes it live", async () => {
    const t = await accepted([["red", "cap"], ["blue", "bcap"], ["green", "gcap"]]);
    await call("PUT", `/v1/tournaments/${t.id}/divisions/${t.div}/schedule`, { games: plan(["red", "blue", "green"]) });
    const games = [...store.docs.keys()].filter((k) => k.startsWith(`tournaments/${t.id}/divisions/${t.div}/games/`)).sort();
    const play = async (path: string, i: number) => {
      const g = store.doc(path)!;
      const gameId = path.split("/").pop();
      const captain = (team: unknown) => ({ red: "cap", blue: "bcap", green: "gcap" })[String(team)]!;
      const score = { scoreA: 15, scoreB: 10 - i };
      await call("POST", `/v1/tournaments/${t.id}/divisions/${t.div}/games/${gameId}/report`, score, captain(g.teamA));
      expect((await call("POST", `/v1/tournaments/${t.id}/divisions/${t.div}/games/${gameId}/confirm`, score, captain(g.teamB))).status).toBe(204);
    };
    await play(games[0], 0);
    expect(store.doc(`tournaments/${t.id}`)?.status).toBe("live");
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.placements).toEqual([]);
    for (const [i, g] of games.slice(1).entries()) await play(g, i + 1);
    expect(store.doc(`tournaments/${t.id}/divisions/${t.div}`)?.placements).toHaveLength(3);
    expect(store.doc(`tournaments/${t.id}`)?.status).toBe("finished");
  });
});

describe("the team page's Finish entry (toFinish)", () => {
  it("lists entries missing a roster or fee before the event, for the team's admins; complete ones drop off", async () => {
    const fee = { amountCents: 25000, currency: "USD", instructions: "", dueAt: null, payerCoversFees: false };
    const t = await open({ bidFee: fee, format: { settings, level: "club", maxTeams: 8, minRoster: 3 } });
    await enter(t.id, t.div, "red", "cap");
    store.put(`teams/red/tournamentEntries/${t.id}`, { name: "Spring Fling", status: "applied" });
    const list = async () => (await call("GET", "/v1/teams/red/tournament-invites", undefined, "cap")).json().toFinish;
    expect(await list()).toEqual([expect.objectContaining({ tournamentId: t.id, status: "applied", rosterSet: false, paid: false, overdue: false })]);
    await call("PUT", `/v1/tournaments/${t.id}/entries/red/roster`, { playerIds: ["p0", "p1", "p2"] }, "cap");
    expect(await list()).toEqual([expect.objectContaining({ rosterSet: true, paid: false })]);
    store.put(`tournaments/${t.id}/payments/red`, { paid: true });
    expect(await list()).toEqual([]);
  });
});
