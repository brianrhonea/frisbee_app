import { describe, expect, it } from "vitest";

import {
  changedGameEvent,
  changedDetails,
  entryChange,
  entryRecord,
  eventDetails,
  eventIdFor,
  gameTeams,
  isLeagueGameEvent,
  leagueEventId,
  leagueGameEvent,
  newEvent,
  newLeagueGameEvent,
  recordUpdate,
} from "../../src/tournaments/model";

const tournament = {
  name: "Lone Star Classic",
  hostName: "Austin Ultimate",
  startsOn: new Date("2026-12-05T00:00:00Z"),
  endsOn: new Date("2026-12-06T00:00:00Z"),
  location: "Zilker Park",
};

describe("tournament entries on team schedules", () => {
  it("adds the tournament when an entry is accepted, removes it when it isn't any more", () => {
    expect(entryChange({ status: "applied" }, { status: "accepted" })).toBe("add");
    expect(entryChange(undefined, { status: "accepted" })).toBe("add");
    expect(entryChange({ status: "accepted" }, { status: "withdrawn" })).toBe("remove");
    expect(entryChange({ status: "accepted" }, undefined)).toBe("remove");
    expect(entryChange({ status: "accepted" }, { status: "accepted", seed: 2 })).toBeNull();
    expect(entryChange({ status: "invited" }, { status: "waitlisted" })).toBeNull();
  });

  it("makes a Tournament event linked to the tournament", () => {
    const e = newEvent("t1", tournament, { kind: "team" });
    expect(eventIdFor("t1")).toBe("tournament_t1");
    expect(e).toMatchObject({
      title: "Lone Star Classic",
      type: "tournament",
      startsAt: tournament.startsOn,
      endsAt: tournament.endsOn,
      location: "Zilker Park",
      tournamentId: "t1",
      public: false,
      rsvps: {},
    });
    expect(e.notes).toContain("Hosted by Austin Ultimate");
    expect(e).not.toHaveProperty("audience");
  });

  it("shows it to everyone in a school or club community", () => {
    expect(newEvent("t1", tournament, { kind: "organization" }).audience).toEqual(["everyone"]);
  });

  it("keeps details valid for the rules", () => {
    const d = eventDetails({ ...tournament, name: "x".repeat(150), endsOn: new Date("2026-12-01") });
    expect((d.title as string).length).toBe(100);
    expect(d.endsAt).toBeNull();
    expect(eventDetails({ startsOn: tournament.startsOn }).title).toBe("Tournament");
  });

  it("follows only the details the host changed", () => {
    expect(changedDetails(tournament, { ...tournament, status: "live" })).toBeNull();
    expect(changedDetails(tournament, { ...tournament, startsOn: new Date(tournament.startsOn.getTime()) })).toBeNull();
    expect(changedDetails(tournament, { ...tournament, name: "Lone Star Open", location: "Mabry" })).toEqual({
      title: "Lone Star Open",
      location: "Mabry",
    });
    const later = new Date("2026-12-12T00:00:00Z");
    expect(changedDetails(tournament, { ...tournament, startsOn: later, endsOn: later })).toEqual({
      startsAt: later,
      endsAt: later,
    });
  });

  it("keeps a record on the team of every tournament it's entered, whatever the status", () => {
    const t = { ...tournament, hostId: "h1" };
    expect(entryRecord(t, { status: "applied" })).toEqual({
      name: "Lone Star Classic",
      hostId: "h1",
      hostName: "Austin Ultimate",
      startsOn: tournament.startsOn,
      endsOn: tournament.endsOn,
      location: "Zilker Park",
      status: "applied",
    });
    expect(entryRecord(t, { status: "invited" })?.status).toBe("invited");
    expect(entryRecord(t, undefined)).toBeNull();
  });

  it("updates the records only for what the host changed", () => {
    expect(recordUpdate(tournament, { ...tournament, status: "live" })).toBeNull();
    expect(recordUpdate(tournament, { ...tournament, hostName: "ATX" })).toEqual({ hostName: "ATX" });
  });
});

describe("league games on team schedules", () => {
  const league = { name: "Thursday Night", location: "City Park", hostName: "Denver Ultimate" };
  const names = { a: "Reds", b: "Blues" };
  const game = {
    teamA: "a",
    teamB: "b",
    startsAt: new Date("2027-06-03T18:30:00Z"),
    field: 2,
    label: "Week 1",
  };
  const make = (over: Record<string, unknown> = {}, teamId = "a") =>
    leagueGameEvent({ tournamentId: "t1", tournament: league, game: { ...game, ...over }, teamId, names, minutes: 60 });

  it("names the event for the opponent, with place, field and week", () => {
    expect(make()).toEqual({
      title: "vs Blues",
      type: "game",
      startsAt: game.startsAt,
      endsAt: new Date("2027-06-03T19:30:00Z"),
      location: "City Park · Field 2",
      notes: "Week 1 · Thursday Night",
      tournamentId: "t1",
      leagueGame: true,
    });
    expect(make({}, "b")?.title).toBe("vs Reds");
  });

  it("gives each game its own stable id per division, so republishing updates it", () => {
    expect(leagueEventId("t1", "d1", "g001")).toBe("league_t1_d1_g001");
    expect(leagueEventId("t1", "d2", "g001")).not.toBe(leagueEventId("t1", "d1", "g001"));
  });

  it("is only for games between two known teams that have a start time", () => {
    expect(make({ teamB: null })).toBeNull();
    expect(make({ teamA: null, teamB: null })).toBeNull();
    expect(make({ startsAt: null })).toBeNull();
    expect(make({}, "stranger")).toBeNull();
    expect(gameTeams({ teamA: "a", teamB: null })).toEqual(["a"]);
    expect(gameTeams(undefined)).toEqual([]);
  });

  it("copes with a missing field, name or place", () => {
    const bare = leagueGameEvent({
      tournamentId: "t1",
      tournament: { name: "L" },
      game: { teamA: "a", teamB: "z", startsAt: game.startsAt },
      teamId: "a",
      names: {},
      minutes: 0,
    });
    expect(bare).toMatchObject({ title: "vs TBD", location: "", notes: "L" });
    // A game is at least a minute long.
    expect((bare!.endsAt as Date).getTime() - game.startsAt.getTime()).toBe(60_000);
  });

  it("changes only what moved, and nothing for a score report", () => {
    const wanted = make()!;
    const current = { ...newLeagueGameEvent(wanted, undefined), rsvps: { u: "yes" } };
    expect(changedGameEvent(current, wanted)).toBeNull();
    expect(changedGameEvent(current, make({ field: 3 })!)).toEqual({ location: "City Park · Field 3" });
    const later = new Date("2027-06-03T19:30:00Z");
    expect(changedGameEvent(current, make({ startsAt: later })!)).toMatchObject({
      startsAt: later,
      endsAt: new Date("2027-06-03T20:30:00Z"),
    });
    expect(changedGameEvent(undefined, wanted)).toBe(wanted);
  });

  it("starts with no responses, for everyone on an organization's schedule", () => {
    const event = newLeagueGameEvent(make()!, { kind: "organization" });
    expect(event).toMatchObject({ rsvps: {}, reactions: {}, votes: {}, poll: null, public: false, audience: ["everyone"] });
    expect(newLeagueGameEvent(make()!, { kind: "team" })).not.toHaveProperty("audience");
  });

  it("is told apart from other events, which notifications still announce", () => {
    expect(isLeagueGameEvent(make()!)).toBe(true);
    expect(isLeagueGameEvent(newEvent("t1", league, undefined))).toBe(false);
    expect(isLeagueGameEvent(undefined)).toBe(false);
  });
});
