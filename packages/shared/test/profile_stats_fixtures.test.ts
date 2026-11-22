// A profile's Team filter (profile_stats.ts) against the app's
// ProfileStatsChoice (apps/mobile/lib/domain/models/player_profile.dart),
// on the vectors in fixtures/profile_stats (written by
// apps/mobile/test/shared_fixtures/profile_stats_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { profileStatsChoice, type StatTotals } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface ChoiceCase {
  name: string;
  teams: string[];
  stats: Record<string, StatTotals>;
  teamStats: Record<string, Record<string, StatTotals>>;
  team: string | null;
  choice: { options: string[]; team: string | null; seasons: string[]; goals: number };
}

describe("profile Team filter matches the app (fixtures/profile_stats/choice.json)", () => {
  it.each(fixture<ChoiceCase>("profile_stats/choice.json").cases)("$name", (c) => {
    const choice = profileStatsChoice(
      { teams: c.teams.map((id) => ({ id, name: id })), stats: c.stats, teamStats: c.teamStats },
      c.team,
    );
    expect({
      options: choice.options.map((t) => t.id),
      team: choice.team,
      seasons: Object.keys(choice.seasons).sort().reverse(),
      goals: Object.values(choice.seasons).reduce((a, s) => a + (s.goals ?? 0), 0),
    }).toEqual(c.choice);
  });
});
