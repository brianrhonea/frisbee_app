import { describe, expect, it } from "vitest";
import { competitionLevels, isYouthTeam, publicPageOn, publicRosterLevels, rosterIsPublic } from "../src/team.js";

describe("rosterIsPublic", () => {
  it("opens adult teams' rosters", () => {
    for (const level of ["club", "college", "league", "pickup"]) {
      expect(rosterIsPublic({ level })).toBe(true);
      expect(rosterIsPublic({ kind: "team", level })).toBe(true);
    }
  });

  it("keeps youth teams and teams without a level private", () => {
    expect(rosterIsPublic({ level: "youth" })).toBe(false);
    expect(rosterIsPublic({ kind: "team" })).toBe(false);
    expect(rosterIsPublic({ kind: "team", level: "" })).toBe(false);
    expect(rosterIsPublic({ kind: "team", level: "Club" })).toBe(false);
    expect(rosterIsPublic({ kind: "team", level: "elite" })).toBe(false);
  });

  it("keeps groups private, open or not, and unknown kinds", () => {
    for (const kind of ["community", "organization", "league", 1, null]) {
      expect(rosterIsPublic({ kind, level: "club" })).toBe(false);
    }
    expect(rosterIsPublic({ kind: "community", level: "club", requiresApproval: false } as never)).toBe(false);
  });

  it("is private for a missing team", () => {
    expect(rosterIsPublic(null)).toBe(false);
    expect(rosterIsPublic(undefined)).toBe(false);
  });

  it("lists every level but youth, so a new level needs adding on purpose", () => {
    expect([...publicRosterLevels].sort()).toEqual(competitionLevels.filter((l) => l !== "youth").sort());
  });

  it("names youth teams for the website's wording", () => {
    expect(isYouthTeam({ level: "youth" })).toBe(true);
    expect(isYouthTeam({ kind: "community", level: "youth" })).toBe(false);
    expect(isYouthTeam({ level: "club" })).toBe(false);
  });
});

describe("publicPageOn (the Public team page switch)", () => {
  it("is on unless stored as false", () => {
    expect(publicPageOn({})).toBe(true);
    expect(publicPageOn({ publicPage: true })).toBe(true);
    expect(publicPageOn(null)).toBe(true);
    expect(publicPageOn({ publicPage: false })).toBe(false);
  });

  it("closes an adult team's roster while off", () => {
    expect(rosterIsPublic({ kind: "team", level: "club", publicPage: false })).toBe(false);
    expect(rosterIsPublic({ kind: "team", level: "club", publicPage: true })).toBe(true);
  });
});
