// The pure draft and league logic, with the cases of
// firebase/functions/test/tournaments/draft.test.ts and league.test.ts,
// plus the app's balanced draft (team_builder.dart).
import { describe, expect, it } from "vitest";
import {
  autoPick,
  available,
  balancedDraft,
  blankTeams,
  type DraftedTeam,
  draftedTeams,
  draftedTeamsProblem,
  draftPaths,
  draftSecondsLeft,
  leagueDirectoryDoc,
  leagueEntry,
  leagueProblem,
  leagueTeamChat,
  leagueTeamDoc,
  leagueTeamId,
  leagueTeamName,
  madeTeams,
  movePlayer,
  normalizedTeam,
  onTheClock,
  pickProblem,
  type PoolPlayer,
  snakeIndex,
  startDraftRequestSchema,
  startProblem,
  suggestedTeamCount,
  teamsCreated,
  teamsFromDraft,
  withDrafted,
} from "../src/drafts.js";

const p = (uid: string, skill: number, gender: "mmp" | "wmp" | null = null): PoolPlayer => ({ uid, name: uid.toUpperCase(), skill, gender });

describe("snakeIndex", () => {
  // The same table is in the app's test/domain/live_draft_test.dart.
  it("snakes back and forth", () => {
    expect([...Array(9).keys()].map((i) => snakeIndex(3, i))).toEqual([0, 1, 2, 2, 1, 0, 0, 1, 2]);
    expect([...Array(6).keys()].map((i) => snakeIndex(2, i))).toEqual([0, 1, 1, 0, 0, 1]);
  });
});

describe("onTheClock", () => {
  const caps = ["a", "b", "c"];
  it("follows the snake and ends with the pool", () => {
    expect(onTheClock(caps, [], 4)).toBe("a");
    expect(onTheClock(caps, [{ uid: "x", captainId: "a" }], 4)).toBe("b");
    const three = ["x", "y", "z"].map((uid, i) => ({ uid, captainId: caps[i] }));
    expect(onTheClock(caps, three, 4)).toBe("c");
    expect(onTheClock(caps, [...three, { uid: "w", captainId: "c" }], 4)).toBeNull();
  });
});

describe("pickProblem", () => {
  const base = { status: "live", captainIds: ["a", "b"], picks: [{ uid: "x", captainId: "a" }], pool: [p("x", 3), p("y", 3), p("z", 3)], uid: "y" };
  it("allows a free player while live", () => expect(pickProblem(base)).toBeNull());
  it("refuses a double pick, a stranger, and a paused or finished draft", () => {
    expect(pickProblem({ ...base, uid: "x" })).toMatch(/already/);
    expect(pickProblem({ ...base, uid: "q" })).toMatch(/isn't in/);
    expect(pickProblem({ ...base, status: "paused" })).toMatch(/paused/);
    expect(pickProblem({ ...base, status: "done" })).toMatch(/isn't running/);
  });
});

describe("autoPick", () => {
  it("takes the best player left, lowest uid on a tie", () => {
    expect(autoPick([p("b", 3), p("a", 3), p("c", 2)], [], false)?.uid).toBe("a");
    expect(autoPick([], [], false)).toBeNull();
  });
  it("evens out gender in a mixed division", () => {
    const left = [p("m1", 5, "mmp"), p("w1", 3, "wmp")];
    expect(autoPick(left, [p("cap", 4, "mmp")], true)?.uid).toBe("w1");
    expect(autoPick(left, [p("cap", 4, "wmp")], true)?.uid).toBe("m1");
    expect(autoPick([p("m1", 5, "mmp")], [p("cap", 4, "mmp")], true)?.uid).toBe("m1");
  });
});

describe("available and startProblem", () => {
  it("drops picked players", () => {
    expect(available([p("a", 1), p("b", 1)], [{ uid: "a", captainId: "c" }]).map((x) => x.uid)).toEqual(["b"]);
  });
  it("checks captains and pool", () => {
    const accepted = new Set(["a", "b", "c", "d"]);
    expect(startProblem({ captainIds: ["a", "b"], accepted, poolSize: 2 })).toBeNull();
    expect(startProblem({ captainIds: ["a"], accepted, poolSize: 3 })).toMatch(/at least/);
    expect(startProblem({ captainIds: ["a", "a"], accepted, poolSize: 3 })).toMatch(/twice/);
    expect(startProblem({ captainIds: ["a", "z"], accepted, poolSize: 3 })).toMatch(/accepted/);
    expect(startProblem({ captainIds: ["a", "b", "c"], accepted, poolSize: 1 })).toMatch(/enough/);
    const many = Array.from({ length: 17 }, (_, i) => `c${i}`);
    expect(startProblem({ captainIds: many, accepted: new Set(many), poolSize: 40 })).toMatch(/at most 16/);
    expect(startProblem({ captainIds: ["a", "b"], accepted, poolSize: 201 })).toMatch(/at most 200/);
  });
  it("clamps the time per pick like the callable", () => {
    expect(startDraftRequestSchema.parse({ captainIds: [], pickSeconds: 9999 }).pickSeconds).toBe(600);
    expect(startDraftRequestSchema.parse({ captainIds: [], pickSeconds: -5.5 }).pickSeconds).toBe(0);
    expect(startDraftRequestSchema.parse({ captainIds: [] }).pickSeconds).toBe(0);
    expect(startDraftRequestSchema.parse({ captainIds: [], pickSeconds: 90.7 }).pickSeconds).toBe(90);
  });
});

describe("teamsFromDraft", () => {
  it("puts each captain first on their own team", () => {
    const teams = teamsFromDraft({
      captains: [
        { uid: "a", name: "Ana" },
        { uid: "b", name: "Ben" },
      ],
      picks: [
        { uid: "x", captainId: "a" },
        { uid: "y", captainId: "b" },
        { uid: "z", captainId: "b" },
      ],
      names: { x: "Xi", y: "Yo", z: "Zed" },
    });
    expect(teams.map((t) => t.id)).toEqual(["team1", "team2"]);
    expect(teams[0]).toMatchObject({ name: "Team Ana", captainId: "a", playerIds: ["a", "x"] });
    expect(teams[1].playerIds).toEqual(["b", "y", "z"]);
    expect(teams[1].playerNames).toEqual({ b: "Ben", y: "Yo", z: "Zed" });
  });
});

describe("withDrafted", () => {
  it("swaps the drafted teams and keeps registered ones", () => {
    const division = { seeds: ["reg", "team1", "team2"], captains: { reg: ["c"], team1: ["a"], team2: ["b"] } };
    const out = withDrafted(division, ["team1", "team2"], [
      { id: "team1", captainId: "x" },
      { id: "team2", captainId: "y" },
      { id: "team3", captainId: null },
    ]);
    expect(out.seeds).toEqual(["reg", "team1", "team2", "team3"]);
    expect(out.captains).toEqual({ reg: ["c"], team1: ["x"], team2: ["y"], team3: [] });
  });
  it("drops drafted teams that are gone and replaces in place", () => {
    expect(withDrafted({ seeds: ["team2", "reg", "team1"] }, ["team1", "team2"], [{ id: "real1" }]).seeds).toEqual(["reg", "real1"]);
    expect(withDrafted({ seeds: ["team2", "reg", "team1"] }, ["team1", "team2"], [{ id: "r1" }, { id: "r2" }]).seeds).toEqual(["r2", "reg", "r1"]);
  });
});

// ---- league.test.ts --------------------------------------------------------------

const league = { kind: "league", entryType: "players", name: "Thursday Night", hostId: "host1" };
const division = { division: "mixed", level: "league" };
const red: DraftedTeam = { id: "team1", name: "Reds", captainId: "a", playerIds: ["a", "b", "c"], playerNames: { a: "Ana", b: "Ben", c: "Cy" } };
const blue: DraftedTeam = { id: "team2", name: "Blues", captainId: "d", playerIds: ["d", "e"], playerNames: { d: "Di", e: "Eli" } };
const everyone = new Set(["a", "b", "c", "d", "e"]);
const check = (over: Partial<Parameters<typeof leagueProblem>[0]> = {}) =>
  leagueProblem({ tournament: league, division, teams: [red, blue], accepted: everyone, hasGames: false, ...over });

describe("reading the drafted teams", () => {
  it("parses what the app wrote and ignores junk", () => {
    const teams = draftedTeams([{ id: "team1", name: " Reds ", captainId: "a", playerIds: ["a", 2], playerNames: { a: "Ana", 2: 5 } }, null, "x"]);
    expect(teams).toEqual([{ id: "team1", name: "Reds", captainId: "a", playerIds: ["a", "2"], playerNames: { a: "Ana", "2": "" } }]);
    expect(draftedTeams(undefined)).toEqual([]);
  });
  it("knows when the real teams have been made", () => {
    expect(teamsCreated([red, blue])).toBe(false);
    expect(teamsCreated([{ ...red, id: leagueTeamId("t1", "team1") }, { ...blue, id: leagueTeamId("t1", "team2") }])).toBe(true);
    expect(teamsCreated([{ ...red, id: leagueTeamId("t1", "team1") }, blue])).toBe(false);
    expect(teamsCreated([])).toBe(false);
  });
  it("gives a drafted team the same id every time", () => {
    expect(leagueTeamId("t1", "team1")).toBe("league_t1_team1");
    expect(leagueTeamId("t2", "team1")).not.toBe(leagueTeamId("t1", "team1"));
  });
});

describe("when teams can be created", () => {
  it("accepts a clean draft", () => expect(check()).toBeNull());
  it("only for leagues where players sign up", () => {
    expect(check({ tournament: { ...league, kind: "tournament" } })).toMatch(/Only leagues/);
    expect(check({ tournament: { ...league, entryType: "teams" } })).toMatch(/Only leagues/);
    expect(check({ tournament: undefined })).toMatch(/doesn't exist/);
    expect(check({ division: undefined })).toMatch(/doesn't exist/);
  });
  it("not once the schedule is published", () => expect(check({ hasGames: true })).toMatch(/schedule is published/));
  it("needs two teams, each with players and a captain on it", () => {
    expect(check({ teams: [red] })).toMatch(/at least two/);
    expect(check({ teams: [red, { ...blue, playerIds: [] }] })).toMatch(/Blues has no players/);
    expect(check({ teams: [red, { ...blue, captainId: null }] })).toMatch(/needs a captain/);
    expect(check({ teams: [red, { ...blue, captainId: "a" }] })).toMatch(/needs a captain/);
    expect(check({ teams: [red, { ...blue, name: "" }] })).toMatch(/needs a name/);
  });
  it("every player must have an accepted signup, and be on one team", () => {
    expect(check({ accepted: new Set(["a", "b", "c", "d"]) })).toMatch(/Eli isn't accepted/);
    expect(check({ teams: [red, { ...blue, playerIds: ["d", "a"] }] })).toMatch(/more than one team/);
  });
});

describe("the new team", () => {
  it("names it after the host's team and the league, within 80 characters", () => {
    expect(leagueTeamName("Reds", "Thursday Night")).toBe("Reds - Thursday Night");
    const long = leagueTeamName("R".repeat(100), "L".repeat(100));
    expect(long.length).toBeLessThanOrEqual(80);
    expect(long.endsWith(` - ${"L".repeat(30)}`)).toBe(true);
  });
  it("is owned by the captain, with the rest as players", () => {
    expect(leagueTeamDoc({ team: red, tournamentId: "t1", tournament: league, division, city: "Denver", createdAt: "NOW" })).toEqual({
      name: "Reds - Thursday Night",
      division: "mixed",
      level: "league",
      city: "Denver",
      ownerId: "a",
      members: { a: "owner", b: "player", c: "player" },
      memberIds: ["a", "b", "c"],
      memberNames: { a: "Ana", b: "Ben", c: "Cy" },
      createdAt: "NOW",
      leagueId: "t1",
      leagueHostId: "host1",
    });
    expect(leagueTeamDoc({ team: { ...blue, playerNames: {} }, tournamentId: "t1", tournament: league, division, city: "", createdAt: 1 }).memberNames).toEqual({
      d: "Player",
      e: "Player",
    });
  });
  it("stays a youth team when drafted from a youth division, team doc and listing alike", () => {
    const doc = leagueTeamDoc({ team: red, tournamentId: "t1", tournament: league, division: { ...division, level: "youth" }, city: "", createdAt: 1 });
    expect(doc.level).toBe("youth");
    expect(leagueDirectoryDoc(doc).level).toBe("youth");
    expect(leagueTeamDoc({ team: red, tournamentId: "t1", tournament: league, division: { ...division, level: "club" }, city: "", createdAt: 1 }).level).toBe("league");
  });
  it("is listed in the team directory with search keywords", () => {
    const listing = leagueDirectoryDoc(leagueTeamDoc({ team: red, tournamentId: "t1", tournament: league, division, city: "Denver", createdAt: 1 }));
    expect(listing).toMatchObject({ name: "Reds - Thursday Night", division: "mixed", level: "league", city: "Denver" });
    expect(listing.keywords).toEqual(expect.arrayContaining(["r", "red", "reds", "thursday", "denver"]));
  });
  it("starts with General and three voice rooms, like any new team", () => {
    const chat = leagueTeamChat("a", "NOW");
    expect(Object.keys(chat.rooms).sort()).toEqual(["general", "voice-film", "voice-lounge", "voice-sideline"]);
    expect(chat.rooms.general).toEqual({
      name: "General",
      readRoles: ["everyone"],
      writeRoles: ["everyone"],
      readUsers: [],
      writeUsers: [],
      folderId: null,
      position: 0,
      kind: "text",
      createdBy: "a",
      createdAt: "NOW",
    });
    expect(chat.rooms["voice-film"]).toMatchObject({ name: "Film Room", kind: "voice", folderId: "voice", position: 2 });
    expect(chat.folders.voice).toMatchObject({ name: "Voice Channels", position: 1000 });
  });
});

describe("the league's own records", () => {
  it("enters each team as accepted with its captain reporting scores", () => {
    expect(leagueEntry(red, "d1", "NOW")).toEqual({ teamName: "Reds", divisionId: "d1", status: "accepted", captainIds: ["a"], updatedAt: "NOW" });
    expect(leagueEntry({ ...red, captainId: null }, "d1", "NOW").captainIds).toEqual([]);
  });
  it("switches the division's teams, seeds and captains to the real ids, keeping order", () => {
    const made = madeTeams([red, blue], "t1");
    expect(made.seeds).toEqual(["league_t1_team1", "league_t1_team2"]);
    expect(made.captains).toEqual({ league_t1_team1: ["a"], league_t1_team2: ["d"] });
    expect(made.teams[0]).toEqual({ id: "league_t1_team1", name: "Reds", captainId: "a", playerIds: ["a", "b", "c"], playerNames: { a: "Ana", b: "Ben", c: "Cy" } });
    expect(teamsCreated(draftedTeams(made.teams))).toBe(true);
  });
});

// ---- The balanced draft and editing (team_builder.dart, TeamDraftViewModel) ---------

describe("balancedDraft", () => {
  const players = [
    { uid: "a", name: "A", skill: 5, gender: "mmp" as const },
    { uid: "b", name: "B", skill: 4, gender: "wmp" as const },
    { uid: "c", name: "C", skill: 3, gender: "mmp" as const },
    { uid: "d", name: "D", skill: 3, gender: "wmp" as const },
    { uid: "e", name: "E", skill: 2, gender: null },
    { uid: "f", name: "F", skill: 1, gender: "mmp" as const },
  ];
  it("deals even sizes and skill, strongest first, captain the most skilled", () => {
    const teams = balancedDraft(players, blankTeams(2), { seed: 1 });
    expect(teams.map((t) => t.playerIds.length)).toEqual([3, 3]);
    const skill = (t: DraftedTeam) => t.playerIds.reduce((n, id) => n + players.find((x) => x.uid === id)!.skill, 0);
    expect(Math.abs(skill(teams[0]) - skill(teams[1]))).toBeLessThanOrEqual(2);
    expect(teams[0].captainId).toBe("a");
    expect(teams[0].playerNames.a).toBe("A");
  });
  it("is the same for the same seed and evens gender in mixed", () => {
    expect(balancedDraft(players, blankTeams(2), { seed: 7, mixed: true })).toEqual(balancedDraft(players, blankTeams(2), { seed: 7, mixed: true }));
    const teams = balancedDraft(players, blankTeams(2), { seed: 3, mixed: true });
    const wmp = (t: DraftedTeam) => t.playerIds.filter((id) => players.find((x) => x.uid === id)!.gender === "wmp").length;
    expect(teams.map(wmp)).toEqual([1, 1]);
    expect(balancedDraft(players, [], { seed: 1 })).toEqual([]);
  });
  it("makes blank teams after existing ids, and moves players", () => {
    expect(blankTeams(2, [{ id: "team2", name: "X", captainId: null, playerIds: [], playerNames: {} }]).map((t) => t.id)).toEqual(["team3", "team4"]);
    let teams = blankTeams(2);
    teams = movePlayer(teams, { uid: "a", name: "A" }, "team1");
    expect(teams[0]).toMatchObject({ playerIds: ["a"], captainId: "a" });
    teams = movePlayer(movePlayer(teams, { uid: "b", name: "B" }, "team1"), { uid: "a", name: "A" }, "team2");
    expect(teams[0]).toMatchObject({ playerIds: ["b"], captainId: "b" });
    expect(teams[1]).toMatchObject({ playerIds: ["a"], captainId: "a" });
    expect(movePlayer(teams, { uid: "a", name: "A" }, null)[1]).toMatchObject({ playerIds: [], captainId: null });
  });
  it("suggests about one and a half fields per team", () => {
    expect(suggestedTeamCount(42, 7, 16)).toBe(4);
    expect(suggestedTeamCount(3, 7, 16)).toBe(2);
    expect(suggestedTeamCount(200, 4, 8)).toBe(8);
  });
});

describe("saving drafted teams (TeamDraftViewModel._save)", () => {
  const two = [red, blue];
  const ok = { division: { maxTeams: 8, seeds: [] }, teams: two, locked: false };
  it("passes clean teams", () => expect(draftedTeamsProblem(ok)).toBeNull());
  it("refuses once created, fewer than two, over the cap, empty, unnamed or same-named teams", () => {
    expect(draftedTeamsProblem({ ...ok, division: { teams: madeTeams(two, "t").teams } })).toMatch(/teams are made/);
    expect(draftedTeamsProblem({ ...ok, teams: [red] })).toMatch(/at least two/);
    expect(draftedTeamsProblem({ ...ok, division: { maxTeams: 2, seeds: ["reg"] } })).toMatch(/up to 2 teams, and 1 registered/);
    expect(draftedTeamsProblem({ ...ok, teams: [red, { ...blue, playerIds: [] }] })).toMatch(/Blues has no players/);
    expect(draftedTeamsProblem({ ...ok, teams: [red, { ...blue, name: "  " }] })).toMatch(/needs a name/);
    expect(draftedTeamsProblem({ ...ok, teams: [red, { ...blue, name: "reds " }] })).toMatch(/different/);
  });
  it("once the schedule is out, keeps the same teams", () => {
    expect(draftedTeamsProblem({ ...ok, division: { maxTeams: 8, seeds: [], teams: two }, locked: true })).toBeNull();
    expect(draftedTeamsProblem({ ...ok, division: { maxTeams: 8, seeds: [], teams: [red] }, locked: true })).toMatch(/only be adjusted/);
  });
  it("saves trimmed names and a captain", () => {
    expect(normalizedTeam({ ...blue, name: " Blues ", captainId: null })).toMatchObject({ name: "Blues", captainId: "d" });
  });
});

describe("the clock and paths", () => {
  it("counts down only while live with a limit", () => {
    const at = "2026-11-14T12:00:00.000Z";
    const t0 = Date.parse(at);
    expect(draftSecondsLeft({ pickSeconds: 60, status: "live", turnStartedAt: at }, t0 + 15_500)).toBe(45);
    expect(draftSecondsLeft({ pickSeconds: 60, status: "live", turnStartedAt: at }, t0 + 99_000)).toBe(0);
    expect(draftSecondsLeft({ pickSeconds: 0, status: "live", turnStartedAt: at }, t0)).toBeNull();
    expect(draftSecondsLeft({ pickSeconds: 60, status: "paused", turnStartedAt: at }, t0)).toBeNull();
  });
  it("encodes ids", () => expect(draftPaths.draftPicks("t/1", "d")).toBe("/v1/tournaments/t%2F1/divisions/d/draft/picks"));
});
