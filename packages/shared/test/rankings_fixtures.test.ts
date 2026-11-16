// The Rankings page's filters (rankings.ts) against the app's RankingChoice
// (apps/mobile/lib/domain/models/ranking.dart), on the vectors in
// fixtures/rankings (written by apps/mobile/test/shared_fixtures/
// rankings_fixtures_test.dart), plus the visitors' answer schema.
import { describe, expect, it } from "vitest";
import {
  chooseRanking,
  parseRankingKey,
  publicRankingsSchema,
  rankedLevels,
  rankingLabel,
  rankingsHref,
  rankingWantFromQuery,
} from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface ChoiceCase {
  name: string;
  keys: string[];
  query: { level?: string; division?: string; d?: string };
  want: { level: string | null; division: string | null };
  choice: { key: string; level: string; division: string; levels: string[]; divisions: string[] } | null;
}

describe("ranking filters match the app (fixtures/rankings/choice.json)", () => {
  it.each(fixture<ChoiceCase>("rankings/choice.json").cases)("$name", (c) => {
    const want = rankingWantFromQuery(c.query);
    expect({ level: want.level ?? null, division: want.division ?? null }).toEqual(c.want);
    expect(chooseRanking(c.keys, want)).toEqual(c.choice);
  });
});

describe("ranked levels", () => {
  it("never include youth", () => {
    expect(rankedLevels).not.toContain("youth");
    expect(parseRankingKey("youth-mixed")).toBeNull();
    expect(chooseRanking(["youth-mixed", "youth-open"])).toBeNull();
  });

  it("label and link a ranking", () => {
    expect(rankingLabel("college", "women")).toBe("College Women");
    expect(rankingsHref("club", "mixed")).toBe("/rankings?level=club&division=mixed");
  });
});

describe("publicRankingsSchema", () => {
  const ranking = {
    key: "club-mixed",
    level: "club",
    division: "mixed",
    minGames: 5,
    updatedAt: null,
    teams: [{ rank: 1, teamId: "t1", name: "Alpha", rating: 1200, wins: 6, losses: 1 }],
  };

  it("takes a ranking", () => {
    expect(publicRankingsSchema.parse({ rankings: [ranking] })).toEqual({ rankings: [ranking] });
  });

  it("refuses youth and any extra field", () => {
    expect(() => publicRankingsSchema.parse({ rankings: [{ ...ranking, level: "youth", key: "youth-mixed" }] })).toThrow();
    expect(() => publicRankingsSchema.parse({ rankings: [{ ...ranking, teams: [{ ...ranking.teams[0], players: [] }] }] })).toThrow();
  });
});
