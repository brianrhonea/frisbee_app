// A league's schedule by week (F30), mirroring the app's
// test/domain/league_weeks_test.dart case for case.
import { describe, expect, it } from "vitest";
import { currentWeekIndex, leagueNights, leagueWeekLabel, leagueWeeks } from "../src/league_weeks.js";
import type { GameStage } from "../src/tournament_engine.js";

type G = { id: string; startsAt: Date | null; stage: GameStage };
const day = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const game = (id: string, startsAt: string | null, stage: GameStage = "pool"): G => ({
  id,
  startsAt: startsAt ? new Date(startsAt) : null,
  stage,
});

// Tuesdays in May 2027; two games a night on the 4th (two rounds).
const games = [
  game("a", "2027-05-04T18:00:00"),
  game("b", "2027-05-04T19:00:00"),
  game("c", "2027-05-11T18:00:00"),
  // The 18th is skipped.
  game("d", "2027-05-25T18:00:00"),
  game("e", "2027-06-01T18:00:00", "winners"),
  game("f", "2027-06-01T19:00:00", "winners"),
];

describe("leagueWeeks", () => {
  it("groups games by night, numbering the nights", () => {
    const weeks = leagueWeeks(games, day);
    expect(weeks.map((w) => [w.key, w.number, w.games.map((g) => g.id)])).toEqual([
      ["2027-05-04", 1, ["a", "b"]],
      ["2027-05-11", 2, ["c"]],
      ["2027-05-25", 3, ["d"]],
      ["2027-06-01", 4, ["e", "f"]],
    ]);
  });

  it("a night of bracket games is the playoffs", () => {
    const weeks = leagueWeeks(games, day);
    expect(weeks.map((w) => leagueWeekLabel(w))).toEqual(["Week 1", "Week 2", "Week 3", "Week 4 · Playoffs"]);
    expect(leagueWeekLabel(weeks[2], leagueNights(weeks))).toBe("Week 3 of 4");
    expect(leagueWeekLabel(weeks[3], 4)).toBe("Week 4 of 4 · Playoffs");
  });

  it("games with no start come last", () => {
    const weeks = leagueWeeks([game("x", null), ...games.slice(0, 1)], day);
    expect(weeks.map((w) => w.key)).toEqual(["2027-05-04", ""]);
    expect(leagueWeekLabel(weeks[1])).toBe("Not scheduled yet");
    expect(leagueNights(weeks)).toBe(1);
  });

  it("no games, no weeks", () => {
    expect(leagueWeeks([], day)).toEqual([]);
  });
});

describe("currentWeekIndex", () => {
  const weeks = leagueWeeks(games, day);
  it("before the season, the first night", () => {
    expect(currentWeekIndex(weeks, "2027-04-01")).toBe(0);
  });
  it("on game night, tonight", () => {
    expect(currentWeekIndex(weeks, "2027-05-11")).toBe(1);
  });
  it("between nights, the next one", () => {
    expect(currentWeekIndex(weeks, "2027-05-12")).toBe(2);
  });
  it("after the season, the last night", () => {
    expect(currentWeekIndex(weeks, "2027-07-01")).toBe(3);
  });
  it("with no weeks, 0", () => {
    expect(currentWeekIndex([], "2027-05-11")).toBe(0);
  });
});
