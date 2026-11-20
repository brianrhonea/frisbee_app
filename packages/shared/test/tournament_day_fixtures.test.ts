// A team's tournament-day card (tournament_day.ts) against the app's
// TournamentDay (apps/mobile/lib/domain/tournament_engine/tournament_day.dart),
// on the vectors in fixtures/tournament_day (written by
// apps/mobile/test/shared_fixtures/tournament_day_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { engineGame, tournamentDay } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface DayCase {
  name: string;
  team: string;
  games: Array<Record<string, unknown> & { id: string }>;
  now: string;
  live: boolean;
  day: Record<string, unknown> | null;
}

describe("tournament-day card matches the app (fixtures/tournament_day/day.json)", () => {
  it.each(fixture<DayCase>("tournament_day/day.json").cases)("$name", (c) => {
    const d = tournamentDay(
      c.games.map((g) => engineGame(g.id, g)),
      c.team,
      new Date(c.now),
      c.live,
    );
    expect(
      d && {
        phase: d.phase,
        next: d.next?.game.id ?? null,
        opponent: d.next?.opponent ?? null,
        last: d.last?.game.id ?? null,
        lastWon: d.last ? d.last.won : null,
        lastScore: d.last ? [d.last.scoreFor, d.last.scoreAgainst] : null,
        wins: d.wins,
        losses: d.losses,
        pool: d.pool,
        place: d.poolPlace,
        poolSize: d.poolSize,
        due: d.scoreDue?.id ?? null,
        dueKind: d.scoreDueKind,
      },
    ).toEqual(c.day);
  });
});
