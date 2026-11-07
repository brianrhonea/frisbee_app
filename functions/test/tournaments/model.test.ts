import { describe, expect, it } from "vitest";

import {
  changedDetails,
  entryChange,
  entryRecord,
  eventDetails,
  eventIdFor,
  newEvent,
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
