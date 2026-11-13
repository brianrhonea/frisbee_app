import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  createTeamRequestSchema,
  searchKeywords,
  teamNameClashes,
  teamNameKey,
  teamNameProbe,
  teamNameWords,
} from "../src/index.js";

// Written by apps/mobile/test/data/shared_fixtures_test.dart, so these
// check the TypeScript ports give exactly what the app gives.
const vectors: Array<{ name: string; words: string[]; key: string; probe: string[]; keywords: string[] }> =
  JSON.parse(readFileSync(new URL("../fixtures/team_names.json", import.meta.url), "utf8"));

describe("team names match the app (fixtures/team_names.json)", () => {
  it.each(vectors)("$name", (v) => {
    expect(teamNameWords(v.name)).toEqual(v.words);
    expect(teamNameKey(v.name)).toBe(v.key);
    expect(teamNameProbe(v.name)).toEqual(v.probe);
    expect(searchKeywords(v.name)).toEqual(v.keywords);
  });
});

describe("teamNameClashes", () => {
  const listing = { id: "a", name: "TX B.Q.Q.", kind: "team" as const, division: "mixed" as const };

  it("matches spellings of the same name in the same division", () => {
    expect(teamNameClashes(listing, { name: "Texas BQQ", kind: "team", division: "mixed" })).toBe(true);
  });

  it("lets teams in other divisions share a name", () => {
    expect(teamNameClashes(listing, { name: "Texas BQQ", kind: "team", division: "open" })).toBe(false);
  });

  it("ignores other kinds and the team itself", () => {
    expect(teamNameClashes(listing, { name: "Texas BQQ", kind: "community", division: "mixed" })).toBe(false);
    expect(teamNameClashes(listing, { name: "Texas BQQ", kind: "team", division: "mixed", excludeId: "a" })).toBe(false);
  });

  it("groups clash across divisions", () => {
    const group = { id: "g", name: "Austin Pickup", kind: "community" as const, division: "mixed" as const };
    expect(teamNameClashes(group, { name: "austin  pickup", kind: "community", division: "open" })).toBe(true);
  });
});

describe("searchKeywords", () => {
  it("caps prefixes at 20 characters and 100 keywords", () => {
    expect(searchKeywords("a".repeat(30))).toHaveLength(20);
    const many = Array.from({ length: 30 }, (_, i) => `w${i}abcdef`).join(" ");
    expect(searchKeywords(many)).toHaveLength(100);
  });
});

describe("createTeamRequestSchema", () => {
  const ok = { name: "  Haze ", division: "open", level: "club" };

  it("trims and fills defaults", () => {
    expect(createTeamRequestSchema.parse(ok)).toEqual({
      name: "Haze",
      division: "open",
      level: "club",
      city: "",
      kind: "team",
      description: "",
      requiresApproval: false,
      location: null,
      leagueId: null,
    });
  });

  it.each([
    ["an empty name", { ...ok, name: "   " }],
    ["a long name", { ...ok, name: "x".repeat(81) }],
    ["an unknown division", { ...ok, division: "coed" }],
    ["an unknown field", { ...ok, ownerId: "someone-else" }],
    ["a bad location", { ...ok, kind: "community", location: { address: "", lat: 91, lng: 0 } }],
    ["a group in a league", { ...ok, kind: "community", leagueId: "l1" }],
    ["a long description", { ...ok, kind: "community", description: "x".repeat(1001) }],
  ])("rejects %s", (_, body) => {
    expect(createTeamRequestSchema.safeParse(body).success).toBe(false);
  });
});
