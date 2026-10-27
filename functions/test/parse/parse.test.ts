import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  parseCompetitionGroup,
  parseDateRange,
  parseRankSets,
  parseRankings,
  parseTournaments,
} from "../../src/usau/parse";

const fixture = (name: string) =>
  readFileSync(join(__dirname, "..", "fixtures", name), "utf8");

describe("parseDateRange", () => {
  it("parses a two-day range at UTC noon", () => {
    const [s, e] = parseDateRange("\n  Nov 07, 2026 - Nov 08, 2026  ");
    expect(s?.toISOString()).toBe("2026-11-07T12:00:00.000Z");
    expect(e?.toISOString()).toBe("2026-11-08T12:00:00.000Z");
  });

  it("uses start as end for single dates", () => {
    const [s, e] = parseDateRange("Mar 1, 2027");
    expect(s?.toISOString()).toBe("2027-03-01T12:00:00.000Z");
    expect(e).toEqual(s);
  });

  it("returns nulls for garbage", () => {
    expect(parseDateRange("TBA")).toEqual([null, null]);
  });
});

describe("parseCompetitionGroup", () => {
  it.each([
    ["College - Women", "College", "Women"],
    ["High School - Mixed DI", "High School", "Mixed"],
    ["HIgh School - Girls", "High School", "Girls"],
    ["Club - Mixed Division 3", "Club", "Mixed"],
    ["Men Upper Division", "", "Men"],
    ["Dev Division", "", ""],
  ])("%s", (input, level, division) => {
    expect(parseCompetitionGroup(input)).toEqual({ level, division });
  });
});

describe("parseTournaments (real page snapshot)", () => {
  const tournaments = parseTournaments(fixture("tournaments.html"));

  it("finds upcoming and past events", () => {
    expect(tournaments.length).toBeGreaterThan(20);
  });

  it("parses the first upcoming event", () => {
    const t = tournaments.find((x) => x.id === "2026-Coconut-Classic");
    expect(t).toMatchObject({
      name: "2026 Coconut Classic",
      url: "https://play.usaultimate.org/events/2026-Coconut-Classic",
      city: "Freehold and Lawrenceville",
      state: "NJ",
      competitionLevel: "High School",
      divisions: ["Boys", "Girls"],
    });
    expect(t?.startDate?.toISOString()).toBe("2026-11-07T12:00:00.000Z");
    expect(t?.endDate?.toISOString()).toBe("2026-11-08T12:00:00.000Z");
  });

  it("produces Firestore-safe ids", () => {
    for (const t of tournaments) expect(t.id).toMatch(/^[A-Za-z0-9_-]+$/);
  });
});

describe("parseRankSets (real page snapshot)", () => {
  const sets = parseRankSets(fixture("rank_sets.html"));

  it("lists published rank sets once each", () => {
    const keys = sets.map((s) => s.key);
    expect(keys).toContain("Club-Men");
    expect(keys).toContain("College-Women");
    expect(new Set(keys).size).toBe(keys.length);
  });

  it("builds absolute urls and labels", () => {
    expect(sets.find((s) => s.key === "Club-Mixed")).toMatchObject({
      label: "Club Mixed",
      url: "https://play.usaultimate.org/teams/events/team_rankings/?RankSet=Club-Mixed",
    });
  });
});

describe("parseRankings (synthetic fixture)", () => {
  it("maps columns by header name", () => {
    const rows = parseRankings(fixture("rankings_synthetic.html"));
    expect(rows).toHaveLength(3);
    expect(rows[0]).toEqual({
      rank: 1,
      teamName: "Alpha Ultimate",
      rating: 2150,
      wins: 18,
      losses: 2,
      region: "Northwest",
      teamUrl: "https://play.usaultimate.org/teams/events/Eventteam/?TeamId=abc",
    });
    expect(rows[2]).toMatchObject({ rank: 3, teamName: "Gamma", wins: 7, losses: 9 });
  });

  it("returns [] when no rankings table exists", () => {
    expect(parseRankings("<table><tr><th>Foo</th></tr></table>")).toEqual([]);
  });
});
