import { describe, expect, it } from "vitest";

import {
  canManageEvents,
  type DraftTeam,
  defaultChat,
  directoryDoc,
  draftTeams,
  leagueEntry,
  leagueProblem,
  leagueTeamId,
  leagueTeamName,
  madeTeams,
  searchKeywords,
  teamDoc,
  teamsCreated,
} from "../../src/tournaments/league";

const league = { kind: "league", entryType: "players", name: "Thursday Night", hostId: "host1" };
const division = { division: "mixed", level: "league" };

const red: DraftTeam = {
  id: "team1",
  name: "Reds",
  captainId: "a",
  playerIds: ["a", "b", "c"],
  playerNames: { a: "Ana", b: "Ben", c: "Cy" },
};
const blue: DraftTeam = {
  id: "team2",
  name: "Blues",
  captainId: "d",
  playerIds: ["d", "e"],
  playerNames: { d: "Di", e: "Eli" },
};
const everyone = new Set(["a", "b", "c", "d", "e"]);

const check = (over: Partial<Parameters<typeof leagueProblem>[0]> = {}) =>
  leagueProblem({ tournament: league, division, teams: [red, blue], accepted: everyone, hasGames: false, ...over });

describe("who can create a league's teams", () => {
  const host = {
    members: { owner1: "owner", cap1: "captain", p1: "player", p2: "player" },
    memberIds: ["owner1", "cap1", "p1", "p2"],
    memberPerms: { p1: ["manageEvents"], p2: ["manageChats"] },
  };

  it("takes owners, the older coach and captain tiers, and members with Manage events", () => {
    expect(canManageEvents(host, "owner1")).toBe(true);
    expect(canManageEvents(host, "cap1")).toBe(true);
    expect(canManageEvents(host, "p1")).toBe(true);
  });

  it("turns away other members, outsiders and a missing team", () => {
    expect(canManageEvents(host, "p2")).toBe(false);
    expect(canManageEvents(host, "stranger")).toBe(false);
    expect(canManageEvents(undefined, "owner1")).toBe(false);
    // A permission only counts for a member.
    expect(canManageEvents({ ...host, memberIds: [] }, "p1")).toBe(false);
  });
});

describe("reading the drafted teams", () => {
  it("parses what the app wrote and ignores junk", () => {
    const teams = draftTeams([
      { id: "team1", name: " Reds ", captainId: "a", playerIds: ["a", 2], playerNames: { a: "Ana", 2: 5 } },
      null,
      "x",
    ]);
    expect(teams).toEqual([
      { id: "team1", name: "Reds", captainId: "a", playerIds: ["a", "2"], playerNames: { a: "Ana", "2": "" } },
    ]);
    expect(draftTeams(undefined)).toEqual([]);
  });

  it("knows when the real teams have been made", () => {
    expect(teamsCreated([red, blue])).toBe(false);
    expect(teamsCreated([{ ...red, id: leagueTeamId("t1", "team1") }, { ...blue, id: leagueTeamId("t1", "team2") }])).toBe(
      true,
    );
    expect(teamsCreated([{ ...red, id: leagueTeamId("t1", "team1") }, blue])).toBe(false);
    expect(teamsCreated([])).toBe(false);
  });

  it("gives a drafted team the same id every time", () => {
    expect(leagueTeamId("t1", "team1")).toBe("league_t1_team1");
    expect(leagueTeamId("t1", "team1")).toBe(leagueTeamId("t1", "team1"));
    expect(leagueTeamId("t2", "team1")).not.toBe(leagueTeamId("t1", "team1"));
  });
});

describe("when teams can be created", () => {
  it("accepts a clean draft", () => {
    expect(check()).toBeNull();
  });

  it("only for leagues where players sign up", () => {
    expect(check({ tournament: { ...league, kind: "tournament" } })).toMatch(/Only leagues/);
    expect(check({ tournament: { ...league, entryType: "teams" } })).toMatch(/Only leagues/);
    expect(check({ tournament: undefined })).toMatch(/doesn't exist/);
    expect(check({ division: undefined })).toMatch(/doesn't exist/);
  });

  it("not once the schedule is published, since games refer to the draft's ids", () => {
    expect(check({ hasGames: true })).toMatch(/schedule is published/);
  });

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
    const doc = teamDoc({
      team: red,
      tournamentId: "t1",
      tournament: league,
      division,
      city: "Denver",
      createdAt: "NOW",
    });
    expect(doc).toEqual({
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
  });

  it("only has the fields the app's team create writes, plus the league's", () => {
    const doc = teamDoc({ team: blue, tournamentId: "t1", tournament: league, division, city: "", createdAt: 1 });
    const appFields = ["name", "division", "level", "city", "ownerId", "members", "memberIds", "memberNames", "createdAt"];
    expect(Object.keys(doc).filter((k) => !appFields.includes(k)).sort()).toEqual(["leagueHostId", "leagueId"]);
    // A player without a name still gets one.
    const nameless = teamDoc({
      team: { ...blue, playerNames: {} },
      tournamentId: "t1",
      tournament: league,
      division,
      city: "",
      createdAt: 1,
    });
    expect(nameless.memberNames).toEqual({ d: "Player", e: "Player" });
  });

  it("is listed in the team directory with search keywords", () => {
    const doc = teamDoc({ team: red, tournamentId: "t1", tournament: league, division, city: "Denver", createdAt: 1 });
    const listing = directoryDoc(doc);
    expect(listing).toMatchObject({ name: "Reds - Thursday Night", division: "mixed", level: "league", city: "Denver" });
    expect(listing.keywords).toEqual(expect.arrayContaining(["r", "red", "reds", "thursday", "denver"]));
  });

  it("searches like the app: word prefixes, lower case, up to 20 letters and 100 words", () => {
    expect(searchKeywords("Ab-c")).toEqual(["a", "ab", "c"]);
    expect(searchKeywords("x".repeat(30))).toHaveLength(20);
    expect(searchKeywords(Array.from({ length: 30 }, (_, i) => `${i.toString(36)}abcdefg${i}`).join(" "))).toHaveLength(100);
    expect(searchKeywords("  ")).toEqual([]);
  });

  it("starts with General and three voice rooms, like any new team", () => {
    const chat = defaultChat("a", "NOW");
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
    expect(Object.keys(chat.folders)).toEqual(["voice"]);
    expect(chat.folders.voice).toMatchObject({ name: "Voice Channels", position: 1000 });
  });
});

describe("the league's own records", () => {
  it("enters each team as accepted with its captain reporting scores", () => {
    expect(leagueEntry(red, "d1", "NOW")).toEqual({
      teamName: "Reds",
      divisionId: "d1",
      status: "accepted",
      captainIds: ["a"],
      updatedAt: "NOW",
    });
    expect(leagueEntry({ ...red, captainId: null }, "d1", "NOW").captainIds).toEqual([]);
  });

  it("switches the division's teams, seeds and captains to the real ids, keeping order", () => {
    const made = madeTeams([red, blue], "t1");
    expect(made.seeds).toEqual(["league_t1_team1", "league_t1_team2"]);
    expect(made.captains).toEqual({ league_t1_team1: ["a"], league_t1_team2: ["d"] });
    expect(made.teams[0]).toEqual({
      id: "league_t1_team1",
      name: "Reds",
      captainId: "a",
      playerIds: ["a", "b", "c"],
      playerNames: { a: "Ana", b: "Ben", c: "Cy" },
    });
    // Run on its own output it is a no-op, so a retry can't change anything.
    expect(teamsCreated(draftTeams(made.teams))).toBe(true);
  });
});
