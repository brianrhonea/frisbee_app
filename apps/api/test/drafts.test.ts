// Signups, drafted teams, the captains' draft and league teams: the cases
// of firebase/functions/test/server/draft.server.test.ts through the API,
// one test per conjunct of the signups, payments and division rules, and
// the documents a league's new teams start with.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { hostDecides, paymentProblem, playerEdits, playerWithdraws, signupCreateProblem, signupUpdateProblem, validDivision, validSignup } from "../src/drafts/rules.js";
import { serverTime } from "../src/store.js";
import { newTeamDocuments } from "../src/teams/documents.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
const T = "league1";
const DIV = "div1";
let store: FakeStore;
type Res = { status: number; json: () => any };
let call: (method: "POST" | "PUT", url: string, body?: object, uid?: string) => Promise<Res>;

const division = { division: "mixed", level: "league", settings: { playersOnField: 7 }, maxTeams: 8, seeds: [], captains: {}, placements: [], teams: [] };

/** A captains'-draft league with [n] accepted players, p0…, hosted by "host" (director owns it). */
function seed(n = 6) {
  store.put("teams/host", {
    name: "Stall 10",
    kind: "organization",
    ownerId: "director",
    members: { director: "owner", helper: "player", fan: "player" },
    memberIds: ["director", "helper", "fan"],
    memberPerms: { helper: ["manageEvents"] },
    city: "Austin",
  });
  store.put(`tournaments/${T}`, {
    name: "Thursday Night",
    hostId: "host",
    hostName: "Stall 10",
    kind: "league",
    entryType: "players",
    draftMode: "captains",
    status: "registration",
    visibility: "public",
  });
  store.put(`tournaments/${T}/divisions/${DIV}`, division);
  for (let i = 0; i < n; i++) {
    store.put(`tournaments/${T}/signups/p${i}`, {
      name: `Player ${i}`,
      divisionId: DIV,
      skill: 1 + (i % 5),
      gender: i % 2 === 0 ? "mmp" : "wmp",
      status: "accepted",
      createdAt: new Date(now),
      updatedAt: new Date(now),
    });
  }
}

beforeEach(() => {
  store = new FakeStore(() => now);
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
  call = async (method, url, body, uid = "director") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer token:${uid}` } });
    return { status: res.statusCode, json: () => res.json() };
  };
});

const base = `/v1/tournaments/${T}/divisions/${DIV}`;
const draftOf = () => store.doc(`tournaments/${T}/drafts/${DIV}`) as any;
const divisionOf = () => store.doc(`tournaments/${T}/divisions/${DIV}`) as any;
const start = (captainIds: string[], uid = "director", pickSeconds?: number) => call("POST", `${base}/draft`, { captainIds, ...(pickSeconds !== undefined && { pickSeconds }) }, uid);
const pick = (who: string, uid: string) => call("POST", `${base}/draft/picks`, { uid }, who);
const control = (action: string, uid = "director") => call("POST", `${base}/draft/control`, { action }, uid);
const finish = (uid = "director") => call("POST", `${base}/draft/finish`, {}, uid);
const createTeams = (uid = "director") => call("POST", `${base}/league-teams`, {}, uid);

describe("captains' draft (draft.server.test.ts)", () => {
  beforeEach(() => seed());

  it("runs a whole draft and makes the league's teams", async () => {
    expect((await start(["p0", "p1"], "p0")).status).toBe(403);
    const started = await start(["p0", "p1"], "director", 60);
    expect(started.status).toBe(201);
    expect(started.json()).toEqual({ captains: 2, players: 4 });
    let draft = draftOf();
    expect(draft.status).toBe("live");
    expect(draft).toMatchObject({ pickSeconds: 60, mixed: true, startedBy: "director", picks: [], turnStartedAt: new Date(now) });
    expect(Object.keys(draft.pool).sort()).toEqual(["p2", "p3", "p4", "p5"]);
    expect(draft.captains.map((c: any) => c.name).sort()).toEqual(["Player 0", "Player 1"]);
    const details = store.doc(`tournaments/${T}/drafts/${DIV}/details/pool`) as any;
    expect(Object.keys(details.players)).toHaveLength(6);
    expect(details.players.p0).toEqual({ skill: 1, gender: "mmp" });
    // A second start can't wipe it.
    expect((await start(["p2", "p3"])).status).toBe(412);

    const [first, second] = draft.captainIds as string[];
    expect((await pick(second, "p2")).status).toBe(403);
    expect((await pick(first, "p2")).status).toBe(204);
    expect(draftOf().picks).toEqual([{ uid: "p2", captainId: first }]);
    expect((await pick(second, "p2")).status).toBe(412);
    expect((await pick(second, first)).status).toBe(412);

    expect((await control("undo", first)).status).toBe(403);
    expect((await control("undo")).status).toBe(204);
    expect(draftOf().picks).toEqual([]);

    expect((await control("pause")).status).toBe(204);
    expect(draftOf().status).toBe("paused");
    expect((await pick(first, "p2")).status).toBe(412);
    expect((await control("resume")).status).toBe(204);
    for (let i = 0; i < 4; i++) expect((await control("autopick")).status).toBe(204);
    draft = draftOf();
    expect(draft.status).toBe("done");
    // Snake order: first, second, second, first.
    expect(draft.picks.map((x: any) => x.captainId)).toEqual([first, second, second, first]);
    expect((await control("autopick")).status).toBe(412);

    const finished = await finish();
    expect(finished.json()).toEqual({ teams: 2 });
    expect(draftOf().status).toBe("finished");
    const div = divisionOf();
    expect(div.teams).toHaveLength(2);
    expect(div.seeds).toEqual(["team1", "team2"]);
    expect(div.teams[0].captainId).toBe(first);
    expect(div.teams[0].playerIds).toHaveLength(3);
    expect(div.captains).toEqual({ team1: [first], team2: [second] });
    expect((await control("pause")).status).toBe(412);
    expect((await finish()).status).toBe(412);

    const made = await createTeams();
    expect(made.status).toBe(200);
    expect(made.json().created).toBe(2);
    const after = divisionOf();
    const teamId = after.seeds[0] as string;
    expect(teamId).toBe(`league_${T}_team1`);
    const team = store.doc(`teams/${teamId}`) as any;
    expect(team.ownerId).toBe(first);
    expect(team.members[first]).toBe("owner");
    expect(store.doc(`tournaments/${T}/entries/${teamId}`)).toMatchObject({ status: "accepted", captainIds: [first], updatedAt: new Date(now) });
    // Calling again changes nothing.
    expect((await createTeams()).json().created).toBe(0);
    // And the draft can't be started over once the teams exist.
    expect((await start(["p0", "p1"])).status).toBe(412);
  });

  it("keeps teams that registered on their own through the draft and team creation", async () => {
    store.put(`tournaments/${T}/divisions/${DIV}`, { ...division, seeds: ["reserved"], captains: { reserved: ["cap"] } });
    await start(["p0", "p1"]);
    for (let i = 0; i < 4; i++) await control("autopick");
    await finish();
    let div = divisionOf();
    expect(div.seeds).toEqual(["reserved", "team1", "team2"]);
    expect(div.captains.reserved).toEqual(["cap"]);
    await createTeams();
    div = divisionOf();
    expect(div.seeds).toEqual(["reserved", `league_${T}_team1`, `league_${T}_team2`]);
    expect(div.captains.reserved).toEqual(["cap"]);
    expect(Object.keys(div.captains)).toHaveLength(3);
  });

  it("cancelling clears the draft so it can start again", async () => {
    await start(["p0", "p1"]);
    expect((await control("cancel")).status).toBe(204);
    expect(draftOf()).toBeUndefined();
    expect(store.doc(`tournaments/${T}/drafts/${DIV}/details/pool`)).toBeUndefined();
    expect((await control("cancel")).status).toBe(412);
    await start(["p2", "p3"]);
    expect([...draftOf().captainIds].sort()).toEqual(["p2", "p3"]);
  });

  it("refuses captains who aren't accepted and events without a captains' draft", async () => {
    expect((await start(["p0", "stranger"])).status).toBe(412);
    store.put(`tournaments/${T}`, { ...(store.doc(`tournaments/${T}`) as object), draftMode: "balanced" });
    expect((await start(["p0", "p1"])).status).toBe(412);
  });

  it("checks ids, actions and the schedule the way the callables do", async () => {
    expect((await call("POST", `/v1/tournaments/bad.id/divisions/${DIV}/draft`, { captainIds: [] })).json().error.message).toBe("Pick an event.");
    expect((await call("POST", `/v1/tournaments/${T}/divisions/nope/draft`, { captainIds: [] })).status).toBe(404);
    await start(["p0", "p1"]);
    const unknown = await control("explode");
    expect(unknown.status).toBe(400);
    expect(unknown.json().error.message).toBe("Unknown action.");
    // A member with Manage events counts as an organizer; a plain member doesn't.
    expect((await control("pause", "helper")).status).toBe(204);
    expect((await control("resume", "fan")).status).toBe(403);
    expect((await pick("fan", "p2")).status).toBe(403);
    expect((await control("resume", "helper")).status).toBe(204);
    // The host can pick for whoever is on the clock.
    expect((await pick("helper", "p2")).status).toBe(204);
    store.put(`tournaments/${T}/divisions/${DIV}/games/g1`, { order: 1 });
    expect((await finish()).json().error.message).toBe("The schedule is published.");
  });

  it("tells a pick before the start, and a captain picking while paused", async () => {
    expect((await pick("p0", "p2")).json().error.message).toBe("The draft hasn't started.");
    await start(["p0", "p1"]);
    await control("pause");
    const [first] = draftOf().captainIds;
    expect((await pick(first, "p2")).json().error.message).toBe("The draft is paused.");
    expect((await control("pause")).json().error.message).toBe("The draft isn't running.");
    await control("resume");
    expect((await control("resume")).json().error.message).toBe("The draft isn't paused.");
    expect((await control("undo")).json().error.message).toBe("Nothing to undo.");
  });
});

describe("pick rate", () => {
  it("the draft's own bucket takes a whole 200-player draft auto-picked in one minute", async () => {
    // Without the global 120-a-minute cap (limits/writes.ts), which is what still binds a host.
    const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now, writeLimits: false });
    const as = (url: string, body: object) => app.inject({ method: "POST", url, payload: body, headers: { authorization: "Bearer token:director" } });
    seed(202);
    expect((await as(`${base}/draft`, { captainIds: ["p0", "p1"] })).statusCode).toBe(201);
    for (let i = 0; i < 200; i++) expect((await as(`${base}/draft/control`, { action: "autopick" })).statusCode).toBe(204);
    expect(draftOf().status).toBe("done");
  });

  it("with the global cap, a host auto-picking fast isn't stopped at 120 a minute", async () => {
    seed(202);
    expect((await start(["p0", "p1"])).status).toBe(201);
    for (let i = 0; i < 150; i++) expect((await control("autopick")).status).toBe(204);
  });

  it("a stranger hammering picks is counted against the global cap: 429 by the 121st", async () => {
    seed(42);
    await start(["p0", "p1"]);
    const codes: number[] = [];
    for (let i = 0; i < 125; i++) codes.push((await pick("stranger", "p2")).status);
    expect(codes.slice(0, 120)).toEqual(Array(120).fill(403));
    expect(codes[120]).toBe(429);
    // And their other writes are capped too, while the host's picks go on.
    expect((await call("PUT", `/v1/tournaments/${T}/signups/me`, {}, "stranger")).status).toBe(429);
    expect((await control("autopick")).status).toBe(204);
  });

  it("captains alternating fast are only bounded by the pool", async () => {
    seed(42);
    await start(["p0", "p1"]);
    for (let i = 0; i < 40; i++) {
      const d = draftOf();
      const left = Object.keys(d.pool).filter((u) => !d.picks.some((x: any) => x.uid === u));
      const clock = d.captainIds[[0, 1, 1, 0][i % 4]];
      expect((await pick(clock, left[0])).status).toBe(204);
    }
    expect(draftOf().status).toBe("done");
  });

  it("a host can decide on 50 players, two writes each, in a minute", async () => {
    seed(50);
    for (let i = 0; i < 50; i++) {
      expect((await call("PUT", `/v1/tournaments/${T}/signups/p${i}/status`, { status: "waitlisted" })).status).toBe(204);
      expect((await call("PUT", `/v1/tournaments/${T}/signups/p${i}/payment`, { paid: true })).status).toBe(204);
    }
  });

  it("every endpoint needs a signed-in caller", async () => {
    seed();
    const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
    for (const [method, url] of [
      ["PUT", `/v1/tournaments/${T}/signups/me`],
      ["PUT", `/v1/tournaments/${T}/signups/p0/status`],
      ["PUT", `/v1/tournaments/${T}/signups/p0/payment`],
      ["PUT", `${base}/drafted-teams`],
      ["POST", `${base}/league-teams`],
      ["POST", `${base}/draft`],
      ["POST", `${base}/draft/picks`],
      ["POST", `${base}/draft/control`],
      ["POST", `${base}/draft/finish`],
    ] as const) {
      expect((await app.inject({ method, url, payload: {} })).statusCode).toBe(401);
    }
  });
});

describe("league teams (createLeagueTeams)", () => {
  const drafted = [
    { id: "team1", name: "Reds", captainId: "p0", playerIds: ["p0", "p2", "p4"], playerNames: { p0: "Player 0", p2: "Player 2", p4: "Player 4" } },
    { id: "team2", name: "Blues", captainId: "p1", playerIds: ["p1", "p3"], playerNames: { p1: "Player 1", p3: "Player 3" } },
  ];
  beforeEach(() => {
    seed();
    store.put(`tournaments/${T}/divisions/${DIV}`, { ...division, teams: drafted, seeds: ["team1", "team2"], captains: { team1: ["p0"], team2: ["p1"] } });
  });

  it("writes exactly the team, listing, chat and entry the callable writes", async () => {
    const res = await createTeams("helper");
    expect(res.json()).toEqual({ created: 2, teams: [{ teamId: `league_${T}_team1`, name: "Reds" }, { teamId: `league_${T}_team2`, name: "Blues" }] });
    const id = `league_${T}_team1`;
    const at = new Date(now);
    expect(store.doc(`teams/${id}`)).toEqual({
      name: "Reds - Thursday Night",
      division: "mixed",
      level: "league",
      city: "Austin",
      ownerId: "p0",
      members: { p0: "owner", p2: "player", p4: "player" },
      memberIds: ["p0", "p2", "p4"],
      memberNames: { p0: "Player 0", p2: "Player 2", p4: "Player 4" },
      createdAt: at,
      leagueId: T,
      leagueHostId: "host",
    });
    expect(store.doc(`teamDirectory/${id}`)).toMatchObject({ name: "Reds - Thursday Night", division: "mixed", level: "league", city: "Austin" });
    // The same rooms and folder as any new team (teams/documents.ts).
    const fresh = newTeamDocuments("x", { name: "n", division: "mixed", level: "league", city: "", kind: "team" } as never, { uid: "p0", label: "" }, at);
    for (const room of ["general", "voice-lounge", "voice-sideline", "voice-film"]) {
      expect(store.doc(`teams/${id}/chats/${room}`)).toEqual(fresh[`teams/x/chats/${room}`]);
    }
    expect(store.doc(`teams/${id}/chatFolders/voice`)).toEqual(fresh["teams/x/chatFolders/voice"]);
    expect(store.doc(`tournaments/${T}/entries/${id}`)).toEqual({ teamName: "Reds", divisionId: DIV, status: "accepted", captainIds: ["p0"], updatedAt: at });
    expect(divisionOf().captains).toEqual({ [id]: ["p0"], [`league_${T}_team2`]: ["p1"] });
  });

  it("keeps a team an interrupted attempt already made", async () => {
    store.put(`teams/league_${T}_team1`, { name: "Kept", ownerId: "p0", leagueId: T, leagueHostId: "host" });
    expect((await createTeams()).json().created).toBe(1);
    expect(store.doc(`teams/league_${T}_team1`)?.name).toBe("Kept");
    expect(store.doc(`tournaments/${T}/entries/league_${T}_team1`)).toBeDefined();
  });

  it("refuses a team someone else made at a league team's id (412), writing nothing", async () => {
    const before = structuredClone(divisionOf());
    // As the client's team create rule could have made it: leagueId, but no server-only leagueHostId.
    for (const squat of [
      { name: "Mine", ownerId: "squatter", leagueId: T },
      { name: "Mine", ownerId: "p0", leagueId: T },
      { name: "Mine", ownerId: "squatter", leagueId: T, leagueHostId: "host" },
      { name: "Mine", ownerId: "p0", leagueId: "other", leagueHostId: "host" },
      { name: "Mine", ownerId: "p0", leagueId: T, leagueHostId: "elsewhere" },
    ]) {
      store.put(`teams/league_${T}_team1`, squat);
      const res = await createTeams();
      expect(res.status).toBe(412);
      expect(res.json().error.message).toMatch(/already uses the id for Reds/);
      expect(store.doc(`tournaments/${T}/entries/league_${T}_team1`)).toBeUndefined();
      expect(store.doc(`teams/league_${T}_team2`)).toBeUndefined();
      expect(divisionOf()).toEqual(before);
    }
  });

  it("refuses non-organizers, tournaments, a published schedule and unaccepted players", async () => {
    expect((await createTeams("fan")).json().error.message).toBe("Only the league's organizers can create its teams.");
    expect((await call("POST", `/v1/tournaments/x.y/divisions/${DIV}/league-teams`, {})).json().error.message).toBe("Pick a league.");
    store.put(`tournaments/${T}/signups/p4`, { ...(store.doc(`tournaments/${T}/signups/p4`) as object), status: "withdrawn" });
    expect((await createTeams()).json().error.message).toBe("Player 4 isn't accepted for this division.");
    store.put(`tournaments/${T}/divisions/${DIV}/games/g1`, { order: 1 });
    expect((await createTeams()).json().error.message).toMatch(/schedule is published/);
    store.put(`tournaments/${T}`, { ...(store.doc(`tournaments/${T}`) as object), kind: "tournament" });
    expect((await createTeams()).json().error.message).toMatch(/Only leagues/);
  });

  it("refuses a drafted team id that isn't a document id", async () => {
    store.put(`tournaments/${T}/divisions/${DIV}`, { ...division, teams: [drafted[0], { ...drafted[1], id: "a/b" }] });
    expect((await createTeams()).status).toBe(400);
    expect(store.doc(`teams/league_${T}_team1`)).toBeUndefined();
  });
});

describe("saving drafted teams", () => {
  const teams = [
    { id: "team1", name: " Reds ", captainId: null, playerIds: ["p0", "p2"], playerNames: { p0: "Player 0", p2: "Player 2" } },
    { id: "team2", name: "Blues", captainId: "p3", playerIds: ["p1", "p3"], playerNames: { p1: "Player 1", p3: "Player 3" } },
  ];
  const save = (body: object, uid = "director") => call("PUT", `${base}/drafted-teams`, body, uid);
  beforeEach(() => seed());

  it("writes teams, seeds and captains for the organizers", async () => {
    expect((await save({ teams }, "fan")).status).toBe(403);
    expect((await save({ teams })).status).toBe(204);
    const d = divisionOf();
    expect(d.teams[0]).toEqual({ id: "team1", name: "Reds", captainId: "p0", playerIds: ["p0", "p2"], playerNames: { p0: "Player 0", p2: "Player 2" } });
    expect(d.seeds).toEqual(["team1", "team2"]);
    expect(d.captains).toEqual({ team1: ["p0"], team2: ["p3"] });
  });

  it("refuses what the app refuses before saving", async () => {
    expect((await save({ teams: [teams[0]] })).json().error.message).toBe("Make at least two teams.");
    expect((await save({ teams: [teams[0], { ...teams[1], name: "reds" }] })).json().error.message).toBe("Team names must be different.");
    expect((await save({ teams: [teams[0], { ...teams[1], id: "x/y" }] })).status).toBe(400);
    // Real league teams' ids are the server's: a client can't make its teams look created.
    expect((await save({ teams: [teams[0], { ...teams[1], id: `league_${T}_team2` }] })).status).toBe(400);
    expect((await save({ teams: teams.map((t, i) => ({ ...t, id: `league_${T}_team${i + 1}` })) })).status).toBe(400);
    await save({ teams });
    store.put(`tournaments/${T}/divisions/${DIV}/games/g1`, { order: 1 });
    expect((await save({ teams: [...teams, { id: "team3", name: "Greens", captainId: null, playerIds: ["p4"], playerNames: {} }] })).json().error.message).toMatch(/only be adjusted/);
    expect((await save({ teams: [teams[1], { ...teams[0], name: "Reds 2" }] })).status).toBe(204);
  });

  it("refuses a division the rule would", async () => {
    store.put(`tournaments/${T}/divisions/${DIV}`, { ...division, placements: undefined });
    const { placements: _, ...noPlacements } = division;
    store.put(`tournaments/${T}/divisions/${DIV}`, noPlacements);
    expect((await save({ teams })).status).toBe(400);
  });
});

describe("signups through the API", () => {
  beforeEach(() => seed(0));
  const mine = (body: object, uid = "sam") => call("PUT", `/v1/tournaments/${T}/signups/me`, body, uid);
  const status = (uid: string, s: string, by = "director") => call("PUT", `/v1/tournaments/${T}/signups/${uid}/status`, { status: s }, by);

  it("signs up, edits while waiting, withdraws and signs back up", async () => {
    expect((await mine({ divisionId: DIV, skill: 4, gender: "wmp" }, "sam:Sam Lee")).json()).toEqual({ status: "applied" });
    expect(store.doc(`tournaments/${T}/signups/sam`)).toEqual({ name: "Sam Lee", divisionId: DIV, skill: 4, gender: "wmp", status: "applied", createdAt: new Date(now), updatedAt: new Date(now) });
    expect((await mine({ divisionId: DIV, skill: 2 })).status).toBe(200);
    expect(store.doc(`tournaments/${T}/signups/sam`)).toMatchObject({ skill: 2, gender: null, status: "applied" });
    expect((await status("sam", "withdrawn", "sam")).status).toBe(204);
    expect((await status("sam", "withdrawn", "sam")).status).toBe(412);
    expect((await mine({ divisionId: DIV, skill: 3 })).json()).toEqual({ status: "applied" });
  });

  it("names the player from their account, never their email", async () => {
    store.put("users/kim", { username: "kimmy" });
    await mine({ divisionId: DIV, skill: 3 }, "kim");
    expect(store.doc(`tournaments/${T}/signups/kim`)?.name).toBe("kimmy");
    await mine({ divisionId: DIV, skill: 3 }, "zed");
    expect(store.doc(`tournaments/${T}/signups/zed`)?.name).toBe("Player");
  });

  it("lets the host decide, and keeps an accepted player's answers fixed", async () => {
    await mine({ divisionId: DIV, skill: 3 });
    expect((await status("sam", "accepted", "fan")).status).toBe(403);
    expect((await status("sam", "accepted", "helper")).status).toBe(204);
    expect((await mine({ divisionId: DIV, skill: 5 })).status).toBe(412);
    expect((await status("ghost", "accepted")).status).toBe(404);
    expect((await status("sam", "maybe")).status).toBe(400);
  });

  it("refuses closed, invite-only and team-entry events, and unknown divisions", async () => {
    expect((await mine({ divisionId: "nope", skill: 3 })).status).toBe(404);
    expect((await mine({ divisionId: DIV, skill: 6 })).status).toBe(400);
    store.put(`tournaments/${T}`, { ...(store.doc(`tournaments/${T}`) as object), visibility: "inviteOnly" });
    expect((await mine({ divisionId: DIV, skill: 3 })).status).toBe(403);
    store.put(`tournaments/${T}`, { ...(store.doc(`tournaments/${T}`) as object), visibility: "public", status: "scheduled" });
    expect((await mine({ divisionId: DIV, skill: 3 })).json().error.message).toBe("Signups are closed.");
    expect((await call("PUT", "/v1/tournaments/ghost/signups/me", { divisionId: DIV, skill: 3 }, "sam")).status).toBe(404);
  });

  it("marks fees paid for organizers only, keeping the note", async () => {
    store.put(`tournaments/${T}/payments/sam`, { paid: false, paidAt: null, note: "Venmo" });
    const pay = (paid: boolean, by = "director") => call("PUT", `/v1/tournaments/${T}/signups/sam/payment`, { paid }, by);
    expect((await pay(true, "sam")).status).toBe(403);
    expect((await pay(true)).status).toBe(204);
    expect(store.doc(`tournaments/${T}/payments/sam`)).toEqual({ paid: true, paidAt: new Date(now), note: "Venmo" });
    await pay(false);
    expect(store.doc(`tournaments/${T}/payments/sam`)).toEqual({ paid: false, paidAt: null, note: "Venmo" });
  });
});

// ---- The rules, one conjunct at a time -------------------------------------------------

const open = { entryType: "players", status: "registration", visibility: "public" };
const signup = { name: "Sam", divisionId: DIV, skill: 3, gender: null, status: "applied", createdAt: serverTime, updatedAt: serverTime };
const player = { uid: "sam", userId: "sam", tournament: open, manages: false };
const stored = { ...signup, createdAt: new Date(now), updatedAt: new Date(now) };

describe("validSignup", () => {
  it("passes a good signup, with or without gender", () => {
    expect(validSignup(signup)).toBeNull();
    const { gender: _, ...noGender } = signup;
    expect(validSignup(noGender)).toBeNull();
  });
  it.each([
    ["keys hasOnly", { extra: 1 }],
    ["name is string", { name: 5 }],
    ["name size > 0", { name: "" }],
    ["name size <= 100", { name: "x".repeat(101) }],
    ["divisionId is string", { divisionId: 1 }],
    ["divisionId size > 0", { divisionId: "" }],
    ["divisionId size <= 100", { divisionId: "d".repeat(101) }],
    ["skill is int", { skill: 2.5 }],
    ["skill >= 1", { skill: 0 }],
    ["skill <= 5", { skill: 6 }],
    ["gender in [null, mmp, wmp]", { gender: "x" }],
    ["status in list", { status: "maybe" }],
    ["updatedAt == request.time", { updatedAt: new Date(now) }],
  ])("refuses when %s fails", (_, over) => {
    expect(validSignup({ ...signup, ...over })).not.toBeNull();
  });
});

describe("playerSignsUp", () => {
  it("passes a player signing themself up", () => expect(signupCreateProblem(player, signup, true)).toBeNull());
  it("validSignup", () => expect(signupCreateProblem(player, { ...signup, skill: 9 }, true)?.code).toBe("invalid_argument"));
  it("uid() == userId", () => expect(signupCreateProblem({ ...player, uid: "other" }, signup, true)?.code).toBe("permission_denied"));
  it("entryType == players", () => expect(signupCreateProblem({ ...player, tournament: { ...open, entryType: "teams" } }, signup, true)?.code).toBe("failed_precondition"));
  it("status == registration", () => expect(signupCreateProblem({ ...player, tournament: { ...open, status: "draft" } }, signup, true)?.message).toBe("Signups are closed."));
  it("visibility == public", () => expect(signupCreateProblem({ ...player, tournament: { ...open, visibility: "inviteOnly" } }, signup, true)?.code).toBe("permission_denied"));
  it("new status == applied", () => expect(signupCreateProblem(player, { ...signup, status: "accepted" }, true)).not.toBeNull());
  it("createdAt == request.time", () => expect(signupCreateProblem(player, { ...signup, createdAt: new Date(now) }, true)).not.toBeNull());
  it("the division exists", () => expect(signupCreateProblem(player, signup, false)?.code).toBe("not_found"));
});

describe("playerEdits", () => {
  const edit = (over: object, before: Record<string, unknown> = stored, ctx: object = {}) => playerEdits({ ...player, ...ctx }, before, { ...before, ...over, updatedAt: serverTime });
  it("passes fixing answers while applied or waitlisted, and coming back", () => {
    expect(edit({ skill: 5 })).toBe(true);
    expect(edit({ skill: 5 }, { ...stored, status: "waitlisted" })).toBe(true);
    expect(edit({ status: "applied" }, { ...stored, status: "withdrawn" })).toBe(true);
  });
  it("uid() == userId", () => expect(edit({ skill: 5 }, stored, { uid: "other" })).toBe(false));
  it("registration is open", () => expect(edit({ skill: 5 }, stored, { tournament: { ...open, status: "seeding" } })).toBe(false));
  it("status stays applied or waitlisted, or withdrawn → applied", () => {
    expect(edit({ status: "accepted" })).toBe(false);
    expect(edit({ skill: 5 }, { ...stored, status: "accepted" })).toBe(false);
    expect(edit({ status: "waitlisted" }, { ...stored, status: "withdrawn" })).toBe(false);
  });
  it("changes only the player's answers", () => expect(edit({ createdAt: serverTime })).toBe(false));
});

describe("playerWithdraws", () => {
  const go = (over: object, before: Record<string, unknown> = stored, ctx: object = {}) => playerWithdraws({ ...player, ...ctx }, before, { ...before, status: "withdrawn", updatedAt: serverTime, ...over });
  it("passes", () => expect(go({})).toBe(true));
  it("uid() == userId", () => expect(go({}, stored, { uid: "other" })).toBe(false));
  it("new status == withdrawn", () => expect(go({ status: "declined" })).toBe(false));
  it("wasn't withdrawn already", () => expect(go({}, { ...stored, status: "withdrawn" })).toBe(false));
  it("changes only status", () => expect(go({ skill: 1 })).toBe(false));
});

describe("hostDecides", () => {
  const host = { ...player, uid: "director", manages: true };
  it("passes", () => expect(hostDecides(host, stored, { ...stored, status: "accepted", updatedAt: serverTime })).toBe(true));
  it("manages(current())", () => expect(hostDecides({ ...host, manages: false }, stored, { ...stored, status: "accepted", updatedAt: serverTime })).toBe(false));
  it("changes only status", () => expect(hostDecides(host, stored, { ...stored, skill: 5, updatedAt: serverTime })).toBe(false));
  it("the update still needs a valid signup", () => {
    expect(signupUpdateProblem(host, stored, { ...stored, status: "accepted", updatedAt: serverTime })).toBeNull();
    expect(signupUpdateProblem(host, { ...stored, name: "" }, { ...stored, name: "", status: "accepted", updatedAt: serverTime })).not.toBeNull();
  });
});

describe("payments", () => {
  const ok = { paid: true, paidAt: serverTime, note: "" };
  it("passes", () => expect(paymentProblem(true, ok)).toBeNull());
  it("manages(current())", () => expect(paymentProblem(false, ok)?.code).toBe("permission_denied"));
  it("keys hasOnly", () => expect(paymentProblem(true, { ...ok, x: 1 })).not.toBeNull());
  it("paid is bool", () => expect(paymentProblem(true, { ...ok, paid: "yes" })).not.toBeNull());
  it("paidAt null or timestamp", () => {
    expect(paymentProblem(true, { ...ok, paidAt: null })).toBeNull();
    expect(paymentProblem(true, { ...ok, paidAt: "today" })).not.toBeNull();
  });
  it("note is a string up to 200", () => {
    expect(paymentProblem(true, { ...ok, note: 1 })).not.toBeNull();
    expect(paymentProblem(true, { ...ok, note: "n".repeat(201) })).not.toBeNull();
  });
});

describe("validDivision", () => {
  it("passes", () => expect(validDivision(division)).toBeNull());
  it.each([
    ["keys hasOnly", { extra: 1 }],
    ["minRoster null or 2..30", { minRoster: 1 }],
    ["minRoster <= 30", { minRoster: 31 }],
    ["teams is a list", { teams: "x" }],
    ["teams size <= 32", { teams: Array(33).fill({}) }],
    ["division in list", { division: "coed" }],
    ["level in list", { level: "pro" }],
    ["settings is map", { settings: [] }],
    ["maxTeams is int", { maxTeams: 2.5 }],
    ["maxTeams >= 2", { maxTeams: 1 }],
    ["maxTeams <= 64", { maxTeams: 65 }],
    ["seeds is list", { seeds: {} }],
    ["seeds size <= maxTeams", { maxTeams: 2, seeds: ["a", "b", "c"] }],
    ["captains is map", { captains: [] }],
    ["captains size <= 64", { captains: Object.fromEntries(Array.from({ length: 65 }, (_, i) => [`t${i}`, []])) }],
    ["placements is list", { placements: {} }],
    ["placements size <= 64", { placements: Array(65).fill("t") }],
  ])("refuses when %s fails", (_, over) => {
    expect(validDivision({ ...division, ...over })).not.toBeNull();
  });
});
