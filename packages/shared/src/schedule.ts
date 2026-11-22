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
export function scheduleEntryOver(
  startsAt: string | null | undefined,
  endsAt: string | null | undefined,
  now: number,
  defaultLengthMs = scheduleDefaultLengthMs,
): boolean {
  const end = endsAt ? Date.parse(endsAt) : Date.parse(startsAt ?? "") + defaultLengthMs;
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
 * once by key, with a start, not over (live meetings never are; as the
 * app's personal schedule, an entry without an end is over once it has
 * started, unlike the team schedule's two hours), before
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
    if (!i.live && scheduleEntryOver(i.startsAt, i.endsAt, opts.now, 0)) continue;
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

// Month view (F16) ------------------------------------------------------------

/**
 * The days of [month]'s grid, Monday first, at local midnight: from the
 * Monday on or before the 1st to the Sunday on or after the last day
 * (the app's monthGrid).
 */
export function monthGrid(month: Date): Date[] {
  const first = new Date(month.getFullYear(), month.getMonth(), 1);
  const last = new Date(month.getFullYear(), month.getMonth() + 1, 0);
  const mondayIndex = (d: Date) => (d.getDay() + 6) % 7;
  const start = new Date(first.getFullYear(), first.getMonth(), 1 - mondayIndex(first));
  const end = new Date(last.getFullYear(), last.getMonth(), last.getDate() + (6 - mondayIndex(last)));
  const out: Date[] = [];
  for (let d = start; d <= end; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) out.push(d);
  return out;
}

/**
 * The Monday-first week [day] is in, local midnights: its row of the
 * month grid (the app's weekOf).
 */
export function weekOf(day: Date): Date[] {
  const monday = new Date(day.getFullYear(), day.getMonth(), day.getDate() - ((day.getDay() + 6) % 7));
  return Array.from({ length: 7 }, (_, i) => new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i));
}

/** Whether [a] and [b] fall on the same local day. */
export function sameDay(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/**
 * The entries starting on [day] (local), earliest first (the app's
 * ScheduleViewModel.eventsOn): each once by key, matching [filter] and not
 * on a hidden calendar. Finished ones stay, unlike [upcomingSchedule].
 */
export function scheduleOnDay<T extends ScheduleItem>(
  items: readonly T[],
  day: Date,
  opts: Pick<ScheduleOptions, "filter" | "hiddenCalendars"> = {},
): T[] {
  const hidden = new Set(opts.hiddenCalendars ?? []);
  const seen = new Set<string>();
  const out: T[] = [];
  for (const i of items) {
    if (seen.has(i.key)) continue;
    const start = startOf(i);
    if (!Number.isFinite(start) || !sameDay(new Date(start), day)) continue;
    if (!scheduleFilterMatches(i, opts.filter)) continue;
    if (i.calendarId && hidden.has(i.calendarId)) continue;
    seen.add(i.key);
    out.push(i);
  }
  return out.sort((a, b) => startOf(a) - startOf(b) || a.key.localeCompare(b.key));
}
