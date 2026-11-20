// Spots left and Learn progress (discover.ts) against the app's
// lib/domain/models/discover.dart, on the vectors in fixtures/discover
// (written by apps/mobile/test/shared_fixtures/discover_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { learnLessons, learnProgressLabel, learnReadIds, spotsLabel, tournamentSpots } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface SpotsCase {
  name: string;
  left: number;
  cap: number;
  label: string;
  full: boolean;
}

interface LessonsCase {
  lessons: Array<{ id: string; title: string }>;
}

interface ProgressCase {
  name: string;
  read: string[];
  ids: string[];
  label: string;
}

describe("spots left match the app (fixtures/discover/spots.json)", () => {
  it.each(fixture<SpotsCase>("discover/spots.json").cases)("$name", (c) => {
    expect(spotsLabel({ left: c.left, cap: c.cap })).toBe(c.label);
  });
});

describe("Learn lessons and progress match the app (fixtures/discover/learn.json)", () => {
  const f = fixture<LessonsCase | ProgressCase>("discover/learn.json");
  it("has the same lessons, in order", () => {
    expect((f.cases[0] as LessonsCase).lessons).toEqual(learnLessons.map((l) => ({ id: l.id, title: l.title })));
  });
  it.each(f.cases.slice(1) as ProgressCase[])("$name", (c) => {
    expect(learnReadIds(c.read)).toEqual(c.ids);
    expect(learnProgressLabel(c.read)).toBe(c.label);
  });
});

describe("tournamentSpots", () => {
  const open = { status: "registration", entryType: "teams" } as const;
  it("adds each division's cap less its accepted teams", () => {
    expect(
      tournamentSpots(open, [
        { maxTeams: 8, seeds: ["a", "b"] },
        { maxTeams: 4, seeds: ["a", "b", "c", "d", "e"] },
      ]),
    ).toEqual({ left: 6, cap: 12 });
  });
  it("is null unless registration is open for teams, or with no caps", () => {
    expect(tournamentSpots({ status: "seeding", entryType: "teams" }, [{ maxTeams: 8, seeds: [] }])).toBeNull();
    expect(tournamentSpots({ status: "registration", entryType: "players" }, [{ maxTeams: 8, seeds: [] }])).toBeNull();
    expect(tournamentSpots(open, [])).toBeNull();
    expect(tournamentSpots(open, [{ maxTeams: "8", seeds: null }])).toBeNull();
  });
});
