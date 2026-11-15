// The member's schedule (the app's MySchedule): their calendars' events
// plus the events and meetings of every team they're on, merged and
// sorted by start. Platform-neutral so the website and the app's rules
// stay one; the reads themselves happen on each platform.

/** Which entries a schedule shows (ScheduleFilter in the app). */
export type ScheduleFilter = "all" | "team" | "personal";

export const scheduleFilters: ReadonlyArray<readonly [ScheduleFilter, string]> = [
  ["all", "All"],
  ["team", "Team"],
  ["personal", "Personal"],
];

/** How long an entry without an end counts as under way after it starts. */
export const scheduleDefaultLengthMs = 2 * 3_600_000;

/**
 * Whether an entry has finished by [now] (ms): at its end, or two hours
 * after it starts without one (TeamDetailViewModel.upcomingEvents). An
 * entry with no readable time is never over, so it isn't hidden by
 * accident; [upcomingSchedule] drops ones without a start.
 */
export function scheduleEntryOver(startsAt: string | null | undefined, endsAt: string | null | undefined, now: number): boolean {
  const end = endsAt ? Date.parse(endsAt) : Date.parse(startsAt ?? "") + scheduleDefaultLengthMs;
  return Number.isFinite(end) && end < now;
}

/** One entry on the schedule, whatever it came from. */
export interface ScheduleItem {
  /** Unique on the schedule: whose it is, then the event (ScheduleEntry.key). */
  key: string;
  startsAt: string | null | undefined;
  endsAt?: string | null;
  /** A team's event or meeting; personal and calendar entries have none. */
  teamId?: string;
  /** The calendar it's on, for calendar entries. */
  calendarId?: string;
  /** A meeting under way: upcoming until it's ended, whatever its times say. */
  live?: boolean;
}

export interface ScheduleOptions {
  /** Now, in ms. */
  now: number;
  /** Leave out entries starting at or after this (ms), e.g. the calendar window's end. */
  until?: number;
  filter?: ScheduleFilter;
  /** Calendars hidden on this device: their entries are left out. */
  hiddenCalendars?: readonly string[];
}

const startOf = (i: ScheduleItem) => Date.parse(i.startsAt ?? "");

/** Whether an entry belongs under [filter]: Team is a team's events and meetings, Personal everything else. */
export function scheduleFilterMatches(item: ScheduleItem, filter: ScheduleFilter = "all"): boolean {
  return filter === "all" || (filter === "team") === Boolean(item.teamId);
}

/**
 * The entries still to come, soonest first (MySchedule.upcoming): each
 * once by key, with a start, not over (live meetings never are), before
 * [until], matching [filter] and not on a hidden calendar.
 */
export function upcomingSchedule<T extends ScheduleItem>(items: readonly T[], opts: ScheduleOptions): T[] {
  const hidden = new Set(opts.hiddenCalendars ?? []);
  const seen = new Set<string>();
  const out: T[] = [];
  for (const i of items) {
    if (seen.has(i.key)) continue;
    const start = startOf(i);
    if (!Number.isFinite(start)) continue;
    if (!i.live && scheduleEntryOver(i.startsAt, i.endsAt, opts.now)) continue;
    if (opts.until !== undefined && start >= opts.until) continue;
    if (!scheduleFilterMatches(i, opts.filter)) continue;
    if (i.calendarId && hidden.has(i.calendarId)) continue;
    seen.add(i.key);
    out.push(i);
  }
  return out.sort((a, b) => startOf(a) - startOf(b) || a.key.localeCompare(b.key));
}

/** What a team entry's tag says: the team's name when the member is on several, else "Team" (ScheduleTag). */
export function scheduleTeamLabel(teamName: string | undefined, teamCount: number): string {
  return teamCount > 1 && teamName ? teamName : "Team";
}
