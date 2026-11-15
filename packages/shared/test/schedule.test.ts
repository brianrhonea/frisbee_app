// The website's My schedule merge, mirroring the app's MySchedule
// (apps/mobile/lib/ui/schedule/view_models/my_schedule.dart: personal,
// calendar and team entries merged soonest first; meetings until ended),
// ScheduleViewModel's All / Team / Personal filter and
// TeamDetailViewModel.upcomingEvents' two-hour rule for events without an
// end.
import { describe, expect, it } from "vitest";
import {
  scheduleEntryOver,
  scheduleFilterMatches,
  type ScheduleItem,
  scheduleTeamLabel,
  upcomingSchedule,
} from "../src/schedule.js";

const now = Date.parse("2026-11-15T12:00:00Z");
const at = (h: number) => new Date(now + h * 3_600_000).toISOString();

describe("scheduleEntryOver", () => {
  it("is over at its end", () => {
    expect(scheduleEntryOver(at(-3), at(-1), now)).toBe(true);
    expect(scheduleEntryOver(at(-3), at(1), now)).toBe(false);
  });

  it("without an end, is over two hours after it starts", () => {
    expect(scheduleEntryOver(at(-1.5), null, now)).toBe(false);
    expect(scheduleEntryOver(at(-2.5), undefined, now)).toBe(true);
  });

  it("an unreadable time is never over", () => {
    expect(scheduleEntryOver("nope", null, now)).toBe(false);
  });
});

describe("upcomingSchedule", () => {
  const personal: ScheduleItem = { key: "cal-me/a", calendarId: "me", startsAt: at(5) };
  const shared: ScheduleItem = { key: "cal-c2/b", calendarId: "c2", startsAt: at(1) };
  const teamEvent: ScheduleItem = { key: "t1/e", teamId: "t1", startsAt: at(3) };
  const meeting: ScheduleItem = { key: "t2/m", teamId: "t2", startsAt: at(2) };

  it("merges personal, calendar and team entries, soonest first", () => {
    const list = upcomingSchedule([personal, teamEvent, meeting, shared], { now });
    expect(list.map((i) => i.key)).toEqual(["cal-c2/b", "t2/m", "t1/e", "cal-me/a"]);
  });

  it("leaves out finished entries but keeps live meetings", () => {
    const done: ScheduleItem = { key: "t1/old", teamId: "t1", startsAt: at(-5), endsAt: at(-4) };
    const live: ScheduleItem = { key: "t1/live", teamId: "t1", startsAt: at(-5), live: true };
    expect(upcomingSchedule([done, live], { now }).map((i) => i.key)).toEqual(["t1/live"]);
  });

  it("filters to team or personal entries", () => {
    const all = [personal, shared, teamEvent, meeting];
    expect(upcomingSchedule(all, { now, filter: "team" }).map((i) => i.key)).toEqual(["t2/m", "t1/e"]);
    expect(upcomingSchedule(all, { now, filter: "personal" }).map((i) => i.key)).toEqual(["cal-c2/b", "cal-me/a"]);
    expect(scheduleFilterMatches(teamEvent, "all")).toBe(true);
  });

  it("leaves out hidden calendars, never team entries", () => {
    const list = upcomingSchedule([personal, shared, teamEvent], { now, hiddenCalendars: ["c2", "t1"] });
    expect(list.map((i) => i.key)).toEqual(["t1/e", "cal-me/a"]);
  });

  it("stops at the window's end, drops entries without a start and repeats", () => {
    const late: ScheduleItem = { key: "t1/late", teamId: "t1", startsAt: at(100) };
    const noStart: ScheduleItem = { key: "t1/none", teamId: "t1", startsAt: undefined };
    const list = upcomingSchedule([teamEvent, late, noStart, { ...teamEvent }], { now, until: now + 50 * 3_600_000 });
    expect(list.map((i) => i.key)).toEqual(["t1/e"]);
  });
});

describe("scheduleTeamLabel", () => {
  it("names the team only when the member is on several", () => {
    expect(scheduleTeamLabel("Ring", 1)).toBe("Team");
    expect(scheduleTeamLabel("Ring", 2)).toBe("Ring");
    expect(scheduleTeamLabel(undefined, 3)).toBe("Team");
  });
});
