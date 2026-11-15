// Team stats and roster spots, following the statsGames, statsTournaments,
// roster and rosterStatus rules: one test per conjunct of each allow.
import { type SaveStatsGameRequest, statsLimits } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
let store: FakeStore;
let call: (method: "POST" | "PUT" | "DELETE", url: string, body?: object, uid?: string) => Promise<{ status: number; json: () => any }>;
let build: (writeLimits: boolean) => void;

const line = ["p1", "p2", "p3", "p4", "p5", "p6", "p7"];
const game = (g: Partial<SaveStatsGameRequest> = {}): SaveStatsGameRequest => ({
  opponent: "Rival",
  date: "2026-11-14T18:00:00.000Z",
  gameTo: 15,
  tournamentId: null,
  eventId: null,
  points: [{ line, startedOn: "offense", actions: [{ kind: "pickup", playerId: "p1" }, { kind: "goal", playerId: "p2", throwerId: "p1" }], result: "weScored" }],
  finished: false,
  lines: [{ id: "l1", name: "O", players: line, side: "offense" }],
  timeoutsPerHalf: 2,
  timeouts: [{ ours: true, half: 1, point: 0, action: 1 }],
  ...g,
});
const tournament = { name: "Regionals", startDate: "2026-10-01T00:00:00.000Z", location: "Field 3", eventId: null, roster: line, lines: [] };

const team = {
  ownerId: "owner",
  memberIds: ["owner", "coach", "player", "keeper", "legacy", "granted", "admin"],
  members: { owner: "owner", coach: "coach", player: "player", keeper: "player", legacy: "stats", granted: "player", admin: "player", ghost: "player" },
  memberPerms: { granted: ["keepStats"], admin: ["manageTeam"], ghostperm: ["keepStats"] },
  statKeepers: ["keeper", "outsider"],
};

beforeEach(() => {
  store = new FakeStore(() => now);
  build = (writeLimits) => {
    const app = buildApp({
      verifier: new FakeVerifier(),
      users: new FakeUsers(),
      teams: new FakeTeamRepository(),
      store,
      media: new FakeMediaStorage(),
      now: () => now,
      writeLimits,
    });
    call = async (method, url, body, uid = "coach") => {
      const res = await app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer token:${uid}` } });
      return { status: res.statusCode, json: () => res.json() };
    };
  };
  build(true);
  store.put("teams/t1", team);
});

const games = "/v1/teams/t1/stats-games";
const doc = (id: string) => store.doc(`teams/t1/statsGames/${id}`)!;

describe("stats games: canKeepStats", () => {
  it("lets editors, keepStats roles, statKeepers members and legacy stats members save", async () => {
    for (const uid of ["owner", "coach", "granted", "keeper", "legacy"]) {
      expect((await call("POST", games, game(), uid)).status, uid).toBe(201);
    }
  });

  it("refuses plain players, admins without stats, and anyone not in memberIds", async () => {
    for (const uid of ["player", "admin", "outsider", "ghost", "ghostperm", "stranger"]) {
      expect((await call("POST", games, game(), uid)).status, uid).toBe(403);
    }
  });

  it("needs the team to exist", async () => {
    expect((await call("POST", "/v1/teams/nope/stats-games", game())).status).toBe(404);
  });

  it("needs a signed-in caller", async () => {
    build(true);
    const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
    const res = await app.inject({ method: "POST", url: games, payload: game() });
    expect(res.statusCode).toBe(401);
  });
});

describe("stats games: what's stored", () => {
  it("is StatsGame.toMap, with a timestamp date and the server's updatedAt", async () => {
    const { id } = (await call("POST", games, game())).json();
    expect(Object.keys(doc(id)).sort()).toEqual(
      ["date", "eventId", "finished", "gameTo", "lines", "opponent", "points", "timeouts", "timeoutsPerHalf", "tournamentId", "updatedAt"].sort(),
    );
    expect(doc(id).date).toBeInstanceOf(Date);
    expect((doc(id).date as Date).toISOString()).toBe("2026-11-14T18:00:00.000Z");
    expect(doc(id).updatedAt).toEqual(new Date(now));
    expect(doc(id).tournamentId).toBeNull();
    expect((doc(id).points as any[])[0].actions[1]).toEqual({ kind: "goal", playerId: "p2", throwerId: "p1" });
    expect((doc(id).lines as any[])[0].side).toBe("offense");
  });

  it("PUT replaces the whole game; a deleted game is a 404", async () => {
    const { id } = (await call("POST", games, game())).json();
    expect((await call("PUT", `${games}/${id}`, game({ finished: true, points: [] }))).status).toBe(204);
    expect(doc(id).finished).toBe(true);
    expect(doc(id).points).toEqual([]);
    expect((await call("PUT", `${games}/ghost`, game())).status).toBe(404);
    expect((await call("PUT", `${games}/${id}`, game(), "player")).status).toBe(403);
  });

  it("DELETE is for stats keepers, as the rule says", async () => {
    const { id } = (await call("POST", games, game())).json();
    expect((await call("DELETE", `${games}/${id}`, undefined, "player")).status).toBe(403);
    expect((await call("DELETE", `${games}/${id}`, undefined, "keeper")).status).toBe(204);
    expect(store.doc(`teams/t1/statsGames/${id}`)).toBeUndefined();
  });

  it("checks path ids", async () => {
    expect((await call("PUT", `${games}/${encodeURIComponent("a/b")}`, game())).status).toBe(400);
    expect((await call("DELETE", `${games}/__x__`)).status).toBe(400);
  });
});

describe("stats games: one conjunct each", () => {
  const bad = async (body: object) => (await call("POST", games, body)).status;
  it("keys().hasOnly", async () => expect(await bad({ ...game(), updatedBy: "coach" })).toBe(400));
  it("opponent is a string", async () => expect(await bad({ ...game(), opponent: 5 })).toBe(400));
  it("opponent is not empty", async () => expect(await bad(game({ opponent: "" }))).toBe(400));
  it("opponent is at most 100", async () => {
    expect(await bad(game({ opponent: "x".repeat(101) }))).toBe(400);
    expect(await bad(game({ opponent: "x".repeat(100) }))).toBe(201);
  });
  it("date is a timestamp", async () => expect(await bad(game({ date: "soon" }))).toBe(400));
  it("gameTo is an int", async () => expect(await bad(game({ gameTo: 7.5 }))).toBe(400));
  it("gameTo > 0", async () => expect(await bad(game({ gameTo: 0 }))).toBe(400));
  it("gameTo <= 50", async () => {
    expect(await bad(game({ gameTo: 51 }))).toBe(400);
    expect(await bad(game({ gameTo: 50 }))).toBe(201);
  });
  it("tournamentId is null or a string of at most 100", async () => {
    expect(await bad(game({ tournamentId: "x".repeat(101) }))).toBe(400);
    expect(await bad({ ...game(), tournamentId: 3 })).toBe(400);
    expect(await bad(game({ tournamentId: "t9" }))).toBe(201);
  });
  it("eventId is null or a string of at most 100", async () => {
    expect(await bad(game({ eventId: "x".repeat(101) }))).toBe(400);
    expect(await bad(game({ eventId: "e1" }))).toBe(201);
  });
  it("points is a list", async () => expect(await bad({ ...game(), points: {} })).toBe(400));
  it("points.size() <= 150", async () => {
    const p = { line: [], startedOn: "offense" as const, actions: [], result: "theyScored" as const };
    expect(await bad(game({ points: Array(151).fill(p) }))).toBe(400);
    expect(await bad(game({ gameTo: 50, points: Array(150).fill(p) }))).toBe(201);
  });
  it("finished is a bool", async () => expect(await bad({ ...game(), finished: "yes" })).toBe(400));
  it("validLines: a list", async () => expect(await bad({ ...game(), lines: "O" })).toBe(400));
  it("validLines: size() <= 50", async () => {
    const l = { id: "l", name: "L", players: line, side: null };
    expect(await bad(game({ lines: Array(51).fill(l) }))).toBe(400);
    expect(await bad(game({ lines: Array(50).fill(l) }))).toBe(201);
  });
  it("timeoutsPerHalf is an int", async () => expect(await bad(game({ timeoutsPerHalf: 1.5 }))).toBe(400));
  it("timeoutsPerHalf >= 0", async () => expect(await bad(game({ timeoutsPerHalf: -1 }))).toBe(400));
  it("timeoutsPerHalf <= 10", async () => expect(await bad(game({ timeoutsPerHalf: 11 }))).toBe(400));
  it("timeouts is a list", async () => expect(await bad({ ...game(), timeouts: 2 })).toBe(400));
  it("timeouts.size() <= 40", async () => {
    const t = { ours: true, half: 1, point: 0, action: 0 };
    expect(await bad(game({ timeouts: Array(41).fill(t) }))).toBe(400);
    expect(await bad(game({ timeouts: Array(40).fill(t) }))).toBe(201);
  });
  it("beyond the rules: nested shapes and the document size", async () => {
    expect(await bad(game({ points: [{ line, startedOn: "sideways" as never, actions: [], result: null }] }))).toBe(400);
    expect(await bad(game({ points: [{ line, startedOn: "offense", actions: [{ kind: "teleport" as never }], result: null }] }))).toBe(400);
    const actions = Array(statsLimits.actionsPerPoint + 1).fill({ kind: "theirTurnover" });
    expect(await bad(game({ points: [{ line, startedOn: "defense", actions, result: null }] }))).toBe(400);
    const big = Array(statsLimits.actionsPerPoint).fill({ kind: "catch_", playerId: "x".repeat(128), throwerId: "y".repeat(128) });
    // Past the API's 64 KB default body limit but under gameBytes: saved (its own bodyLimit).
    expect(await bad(game({ points: Array(4).fill({ line, startedOn: "offense", actions: big, result: null }) }))).toBe(201);
    // Over gameBytes (900 KB): the schema turns it down.
    expect(await bad(game({ points: Array(7).fill({ line, startedOn: "offense", actions: big, result: null }) }))).toBe(400);
  });
});

describe("stats tournaments", () => {
  const url = "/v1/teams/t1/stats-tournaments";
  const bad = async (body: object) => (await call("POST", url, body)).status;

  it("are saved whole by stats keepers, with a timestamp startDate", async () => {
    expect((await call("POST", url, tournament, "player")).status).toBe(403);
    const res = await call("POST", url, tournament, "keeper");
    expect(res.status).toBe(201);
    const t = store.doc(`teams/t1/statsTournaments/${res.json().id}`)!;
    expect(Object.keys(t).sort()).toEqual(["eventId", "lines", "location", "name", "roster", "startDate", "updatedAt"]);
    expect(t.startDate).toBeInstanceOf(Date);
    expect((await call("PUT", `${url}/${res.json().id}`, { ...tournament, roster: ["p1"] })).status).toBe(204);
    expect(store.doc(`teams/t1/statsTournaments/${res.json().id}`)!.roster).toEqual(["p1"]);
    expect((await call("PUT", `${url}/ghost`, tournament)).status).toBe(404);
  });

  it("keys().hasOnly", async () => expect(await bad({ ...tournament, games: [] })).toBe(400));
  it("name is a string of 1 to 100", async () => {
    expect(await bad({ ...tournament, name: 1 })).toBe(400);
    expect(await bad({ ...tournament, name: "" })).toBe(400);
    expect(await bad({ ...tournament, name: "x".repeat(101) })).toBe(400);
  });
  it("startDate is a timestamp", async () => expect(await bad({ ...tournament, startDate: "never" })).toBe(400));
  it("location is a string of at most 200", async () => {
    expect(await bad({ ...tournament, location: "x".repeat(201) })).toBe(400);
    expect(await bad({ ...tournament, location: 5 })).toBe(400);
  });
  it("eventId is null or a string of at most 100", async () => expect(await bad({ ...tournament, eventId: "x".repeat(101) })).toBe(400));
  it("roster is a list of at most 200", async () => {
    expect(await bad({ ...tournament, roster: "p1" })).toBe(400);
    expect(await bad({ ...tournament, roster: Array(201).fill("p") })).toBe(400);
  });
  it("validLines", async () => expect(await bad({ ...tournament, lines: Array(51).fill({ id: "l", name: "L", players: line, side: null }) })).toBe(400));

  it("deleting one deletes its games and keeps the rest", async () => {
    const { id } = (await call("POST", url, tournament)).json();
    const inIt = (await call("POST", games, game({ tournamentId: id }))).json().id;
    const inIt2 = (await call("POST", games, game({ tournamentId: id }))).json().id;
    const other = (await call("POST", games, game({ tournamentId: "elsewhere" }))).json().id;
    const alone = (await call("POST", games, game())).json().id;
    expect((await call("DELETE", `${url}/${id}`, undefined, "player")).status).toBe(403);
    expect(store.doc(`teams/t1/statsGames/${inIt}`)).toBeDefined();
    expect((await call("DELETE", `${url}/${id}`, undefined, "keeper")).status).toBe(204);
    expect(store.doc(`teams/t1/statsTournaments/${id}`)).toBeUndefined();
    expect(store.doc(`teams/t1/statsGames/${inIt}`)).toBeUndefined();
    expect(store.doc(`teams/t1/statsGames/${inIt2}`)).toBeUndefined();
    expect(store.doc(`teams/t1/statsGames/${other}`)).toBeDefined();
    expect(store.doc(`teams/t1/statsGames/${alone}`)).toBeDefined();
  });
});

describe("roster spots", () => {
  const url = "/v1/teams/t1/roster-players";
  const spot = { name: "Sam", number: 7, position: "cutter", userId: null, paid: true };
  const bad = async (body: object) => (await call("POST", url, body)).status;

  it("admins who manage the team save them with the paid mark apart", async () => {
    expect((await call("POST", url, spot, "keeper")).status).toBe(403);
    expect((await call("POST", url, spot, "stranger")).status).toBe(403);
    const res = await call("POST", url, spot, "admin");
    expect(res.status).toBe(201);
    const id = res.json().id;
    expect(store.doc(`teams/t1/roster/${id}`)).toEqual({ name: "Sam", number: 7, position: "cutter", userId: null });
    expect(store.doc(`teams/t1/rosterStatus/${id}`)).toEqual({ paid: true });
    expect((await call("PUT", `${url}/${id}`, { name: "Sam B", number: null, position: "handler", userId: null })).status).toBe(204);
    expect(store.doc(`teams/t1/roster/${id}`)).toEqual({ name: "Sam B", number: null, position: "handler", userId: null });
    expect(store.doc(`teams/t1/rosterStatus/${id}`)).toEqual({ paid: true });
    expect((await call("PUT", `${url}/ghost`, spot)).status).toBe(404);
  });

  it("keys().hasOnly", async () => expect(await bad({ ...spot, onUsau: true })).toBe(400));
  it("name is a string of 1 to 80", async () => {
    expect(await bad({ ...spot, name: 3 })).toBe(400);
    expect(await bad({ ...spot, name: "" })).toBe(400);
    expect(await bad({ ...spot, name: "x".repeat(81) })).toBe(400);
  });
  it("number is null or an int", async () => expect(await bad({ ...spot, number: 1.5 })).toBe(400));
  it("position is handler, cutter or hybrid", async () => expect(await bad({ ...spot, position: "goalie" })).toBe(400));
  it("rosterStatus: paid is a bool", async () => expect(await bad({ ...spot, paid: "yes" })).toBe(400));

  it("validLink: a member, nobody, or the link it already had", async () => {
    expect(await bad({ ...spot, userId: "stranger" })).toBe(400);
    expect(await bad({ ...spot, userId: "player" })).toBe(201);
    store.put("teams/t1/roster/left", { name: "Gone", number: null, position: "hybrid", userId: "former" });
    expect((await call("PUT", `${url}/left`, { ...spot, userId: "former" })).status).toBe(204);
    expect((await call("PUT", `${url}/left`, { ...spot, userId: "someoneelse" })).status).toBe(400);
  });

  it("delete takes the paid mark too", async () => {
    const id = (await call("POST", url, spot)).json().id;
    expect((await call("DELETE", `${url}/${id}`, undefined, "keeper")).status).toBe(403);
    expect((await call("DELETE", `${url}/${id}`)).status).toBe(204);
    expect(store.doc(`teams/t1/roster/${id}`)).toBeUndefined();
    expect(store.doc(`teams/t1/rosterStatus/${id}`)).toBeUndefined();
  });

  describe("claiming (the member update rule)", () => {
    beforeEach(() => {
      store.put("teams/t1/roster/free", { name: "Free", number: null, position: "hybrid", userId: null });
      store.put("teams/t1/roster/taken", { name: "Taken", number: 3, position: "hybrid", userId: "keeper" });
    });
    const link = (id: string, userId: string | null, uid: string) => call("PUT", `${url}/${id}/link`, { userId }, uid);

    it("isMember", async () => expect((await link("free", "stranger", "stranger")).status).toBe(403));
    it("an unlinked spot, for yourself only", async () => {
      expect((await link("free", "keeper", "player")).status).toBe(403);
      expect((await link("free", "player", "player")).status).toBe(204);
      expect(store.doc("teams/t1/roster/free")).toEqual({ name: "Free", number: null, position: "hybrid", userId: "player" });
    });
    it("letting go of your own, not someone else's", async () => {
      expect((await link("taken", null, "player")).status).toBe(403);
      expect((await link("taken", "player", "player")).status).toBe(403);
      expect((await link("taken", null, "keeper")).status).toBe(204);
      expect(store.doc("teams/t1/roster/taken")!.userId).toBeNull();
    });
    it("admins link any member", async () => {
      expect((await link("taken", "player", "admin")).status).toBe(204);
      expect((await link("taken", "stranger", "admin")).status).toBe(403);
    });
    it("says why a link is refused", async () => {
      const why = async (id: string, userId: string | null, uid: string) => (await link(id, userId, uid)).json().error.message;
      expect(await why("free", "keeper", "player")).toBe("You can only claim a spot for yourself.");
      expect(await why("taken", null, "player")).toBe("This spot is linked to someone else.");
      expect(await why("free", "stranger", "admin")).toBe("Only one of the team's members can be linked to a spot.");
      await link("free", "player", "player");
      expect(await why("free", "keeper", "player")).toBe("You can only unlink yourself from your spot.");
    });
    it("only userId changes, and the spot must exist", async () => {
      expect((await call("PUT", `${url}/free/link`, { userId: "player", name: "X" }, "player")).status).toBe(400);
      expect((await link("ghost", "player", "player")).status).toBe(404);
    });
  });
});

describe("stats write limit", () => {
  it("allows 90 stats writes a minute per member, then 429", async () => {
    const { id } = (await call("POST", games, game())).json();
    for (let i = 2; i <= 90; i++) expect((await call("PUT", `${games}/${id}`, game())).status, `write ${i}`).toBe(204);
    expect((await call("PUT", `${games}/${id}`, game())).status).toBe(429);
    // Its own bucket: other members and other kinds of writes are unaffected.
    expect((await call("PUT", `${games}/${id}`, game(), "keeper")).status).toBe(204);
  });
});
