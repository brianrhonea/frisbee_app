// A league's schedule, a week at a time (F30): its games grouped by game
// night, for the Schedule tab's "‹ Week N ›" stepper, and the week it
// opens on. The app's mirror is lib/domain/tournament_engine/
// league_weeks.dart; both are tested against the same cases.
//
// Weeks are game nights, not rounds: with two games a night a night has
// two rounds, and a skipped week has no night at all.
import { type GameStage, isBracketStage } from "./tournament_engine.js";

/** One night of a league's schedule. */
export interface LeagueWeek<G> {
  /** The night's day (as [dayOf] gives it, e.g. "2027-05-04"), or "" for games with no start yet. */
  key: string;
  /** 1 for the first night. */
  number: number;
  /** Every game that night is a playoff (bracket) game. */
  playoffs: boolean;
  /** In schedule order. */
  games: G[];
}

type WeekGame = { startsAt: Date | null; stage: GameStage };

/**
 * [games] (in schedule order) by night: [dayOf] turns a start into a day
 * key that sorts by date (dayKey on the website, in the page's zone).
 * Games with no start come last, as one more week.
 */
export function leagueWeeks<G extends WeekGame>(games: readonly G[], dayOf: (d: Date) => string): Array<LeagueWeek<G>> {
  const byDay = new Map<string, G[]>();
  for (const g of games) {
    const key = g.startsAt ? dayOf(g.startsAt) : "";
    const list = byDay.get(key);
    if (list) list.push(g);
    else byDay.set(key, [g]);
  }
  const keys = [...byDay.keys()].sort((a, b) => (a === "" ? 1 : b === "" ? -1 : a < b ? -1 : a > b ? 1 : 0));
  return keys.map((key, i) => {
    const list = byDay.get(key)!;
    return { key, number: i + 1, playoffs: list.every((g) => isBracketStage(g.stage)), games: list };
  });
}

/**
 * The week the schedule opens on: the first night on or after [today]
 * (a day key), so tonight's games during game night and next week's
 * after it; once the season is over, its last night.
 */
export function currentWeekIndex(weeks: ReadonlyArray<LeagueWeek<unknown>>, today: string): number {
  const next = weeks.findIndex((w) => w.key !== "" && w.key >= today);
  if (next >= 0) return next;
  const dated = weeks.map((w) => w.key !== "").lastIndexOf(true);
  return dated >= 0 ? dated : 0;
}

/** "Week 3", with [total] (the season's nights) "Week 3 of 8"; "· Playoffs" on a playoff night; or "Not scheduled yet". */
export function leagueWeekLabel(w: LeagueWeek<unknown>, total?: number): string {
  if (w.key === "") return "Not scheduled yet";
  const week = total ? `Week ${w.number} of ${total}` : `Week ${w.number}`;
  return w.playoffs ? `${week} · Playoffs` : week;
}

/** How many nights [weeks] has (games with no start yet aren't one). */
export const leagueNights = (weeks: ReadonlyArray<LeagueWeek<unknown>>) => weeks.filter((w) => w.key !== "").length;
