"use client";
import {
  type CalendarEvent,
  type CalendarEventResult,
  type CalendarEventsResponse,
  type CalendarColor,
  type CalendarInfo,
  type CalendarInvite,
  type CalendarInvitesResponse,
  type CalendarsResponse,
  calendarEventTypes,
  calendarWindowDays,
  type EventType,
  eventTypeLabels,
  monthGrid,
  sameDay,
  type ScheduleFilter,
  type ScheduleItem,
  scheduleFilters,
  scheduleOnDay,
  scheduleTeamLabel,
  type ShareRole,
  shareRoleLabels,
  shareRoles,
  type Repeat,
  upcomingSchedule,
  weekOf,
} from "@stall10/shared";
import Link from "next/link";
import { type FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { colorOf, loadHidden, saveHidden } from "@/lib/calendar";
import { AddToCalendar } from "./AddToCalendar";
import { callApi, problem } from "@/lib/client";
import { type Doc, useLiveQueries } from "@/lib/live";
import { type Meeting, type MeetingData, meetingHref, teamBase, teamMeetingQueries } from "./team/meetings/model";
import { memberViewer, type TeamDoc } from "./team/TeamContext";
import { scheduleMeetings, type TeamEventDoc, teamEventQueries } from "./team/TeamSchedule";
import { useAuth } from "./AuthProvider";
import { type ShareChoice, ShareEventField, shareEvent } from "./team/ShareEvent";
import { fromLocalInput, startOfToday, toLocalInput } from "@/lib/dates";
import { useMyTeams } from "./useMyTeams";
import { browserTimeZone, RepeatField, RepeatNote, repeatFormProblem, scopeQuery, useSeriesScope } from "./Repeat";
import { type PickedPerson, PersonPicker } from "./PersonPicker";
import { ColorPicker } from "./settings/CalendarSettings";
import { meetingAnswer, needsRsvp } from "./RsvpPill";
import "./member.css";
import { Button } from "./ui/Button";
import { EventCard } from "./ui/EventCard";
import { SegmentedTabs } from "./ui/SegmentedTabs";
import { FilterChips } from "./ui/FilterChips";
import { useConfirm } from "@/components/ui/ConfirmDialog";
import { ErrorNote } from "@/components/StatusViews";

const dayMs = 86_400_000;
const canEdit = (c: CalendarInfo | undefined) => c?.role === "owner" || c?.role === "edit";


interface Loaded {
  calendars: CalendarInfo[];
  invites: CalendarInvite[];
  events: CalendarEvent[];
}

/** One team's live events and meetings, as its listeners last answered (undefined while loading or refused). */
interface TeamFeedData {
  events?: Array<Doc<TeamEventDoc>>;
  meetings?: Meeting[];
}

/** An entry on My schedule: a calendar event, or a team's event or meeting (ScheduleEntry). */
type Row = ScheduleItem &
  (
    | { kind: "calendar"; event: CalendarEvent }
    | { kind: "event"; team: Doc<TeamDoc>; event: Doc<TeamEventDoc> }
    | { kind: "meeting"; team: Doc<TeamDoc>; meeting: Meeting }
  );

/** Team entries share one color, as in the app; calendars have their own. */

/** How far back team events are read, so multi-day ones under way stay in (MySchedule.lookBack). */
const lookBackDays = 7;
const teamColor = "var(--team)";

/**
 * Listens to one team's upcoming events and meetings for My schedule, with
 * the same reads (and so the same rules) as the team's own schedule, and
 * hands them up. Renders nothing. A refused or failed read leaves that
 * team out rather than blanking the schedule, as MySchedule logs and goes on.
 */
function TeamFeed({
  team,
  uid,
  lookBack = lookBackDays,
  onData,
}: {
  team: Doc<TeamDoc>;
  uid: string;
  /** Days before today to read from: further back for a past month in the month view. */
  lookBack?: number;
  onData: (teamId: string, data: TeamFeedData | null) => void;
}) {
  const member = memberViewer(team, uid);
  const ev = teamEventQueries(member, false, lookBack);
  const events = useLiveQueries<TeamEventDoc>(`teams/${team.id}/events`, ev.queries, ev.key);
  const mq = teamMeetingQueries(member);
  const meetings = useLiveQueries<MeetingData>(`teams/${team.id}/meetings`, mq.queries, mq.key);
  // The live states change only when a listener answers, so this doesn't loop.
  useEffect(
    () => onData(team.id, { events: events.data, meetings: meetings.data }),
    [team.id, events.data, meetings.data, onData],
  );
  useEffect(() => () => onData(team.id, null), [team.id, onData]);
  return null;
}

/**
 * The member's schedule on the website (the app's MySchedule), like
 * Outlook or Apple Calendar: every calendar they're on (their own and ones
 * they accepted), each in its color and hidden or shown on this browser,
 * with invites to accept, plus the events and meetings of every team
 * they're on, merged soonest first, with the app's All / Team / Personal
 * filter. Calendars go through the API, which checks each calendar's
 * members; team events and meetings are live Firestore reads under the
 * same rules as each team's schedule. Events are added to any calendar the
 * member may change; team events on the team's page.
 */
export function Schedule() {
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const [data, setData] = useState<Loaded | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [hidden, setHidden] = useState<string[]>([]);
  const [editing, setEditing] = useState<(Partial<CalendarEvent> & { calendarId?: string }) | null>(null);
  const [filter, setFilter] = useState<ScheduleFilter>("all");
  // Every team the member is on (watchMyTeams), each listened to by a TeamFeed.
  const teamsLive = useMyTeams<TeamDoc>(user?.uid);
  const [feeds, setFeeds] = useState<Record<string, TeamFeedData>>({});
  const onFeed = useCallback((teamId: string, d: TeamFeedData | null) => {
    setFeeds((f) => {
      if (d) return { ...f, [teamId]: d };
      const next = { ...f };
      delete next[teamId];
      return next;
    });
  }, []);

  // List or Month (the app's Week / Month), kept in this browser; the
  // month shown and the day picked in it.
  const [view, setView] = useState<ScheduleView>("list");
  const [month, setMonth] = useState(() => firstOfMonth(new Date()));
  const [picked, setPicked] = useState(() => startOfToday());
  // "This event or this and following" for deleting a repeating event.
  const scope = useSeriesScope();
  useEffect(() => setView(loadView()), []);
  // Month and Week both read the month grid's range and show the picked day; List is the upcoming run.
  const monthView = view !== "list";
  const weekView = view === "week";
  const grid = monthGrid(month);
  // Calendars are read for the list's window, or the month's whole grid.
  const rangeFrom = monthView ? grid[0].getTime() : startOfToday().getTime() - dayMs;
  const rangeTo = monthView ? grid[grid.length - 1].getTime() + dayMs : rangeFrom + (calendarWindowDays - 1) * dayMs;
  // Team events are read from a week back, or from the grid's first day for a past month.
  const feedLookBack = monthView
    ? Math.max(lookBackDays, Math.ceil((startOfToday().getTime() - grid[0].getTime()) / dayMs))
    : lookBackDays;

  useEffect(() => setHidden(loadHidden()), []);

  // Paging months fast can overlap loads: only the latest one's answer counts.
  const loadSeq = useRef(0);
  const load = useCallback(async () => {
    if (!user) return;
    const seq = ++loadSeq.current;
    const qs = new URLSearchParams({
      from: new Date(rangeFrom).toISOString(),
      to: new Date(rangeTo).toISOString(),
    });
    try {
      const [c, i, e] = await Promise.all([
        callApi<CalendarsResponse>(user, "/v1/me/calendars"),
        callApi<CalendarInvitesResponse>(user, "/v1/me/calendar-invites"),
        callApi<CalendarEventsResponse>(user, `/v1/me/calendar-events?${qs}`),
      ]);
      if (seq !== loadSeq.current) return;
      setData({ calendars: c.calendars, invites: i.invites, events: e.events });
      setError(null);
    } catch (err) {
      if (seq !== loadSeq.current) return;
      setError(problem(err));
    }
  }, [user, rangeFrom, rangeTo]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!user) return null;
  const me = user;

  function toggle(id: string) {
    const next = hidden.includes(id) ? hidden.filter((h) => h !== id) : [...hidden, id];
    setHidden(next);
    saveHidden(next);
  }

  const byId = new Map((data?.calendars ?? []).map((c) => [c.id, c]));
  const writable = (data?.calendars ?? []).filter(canEdit);
  const teams = (teamsLive.data ?? []).filter((t) => t.memberIds?.includes(me.uid));
  const rows: Row[] = [
    ...(data?.events ?? []).map(
      (e): Row => ({
        kind: "calendar",
        key: `cal-${e.calendarId}/${e.id}`,
        calendarId: e.calendarId,
        startsAt: e.startsAt,
        endsAt: e.endsAt,
        event: e,
      }),
    ),
    ...teams.flatMap((t): Row[] => [
      ...(feeds[t.id]?.events ?? []).map(
        (e): Row => ({ kind: "event", key: `${t.id}/${e.id}`, teamId: t.id, startsAt: e.startsAt, endsAt: e.endsAt, team: t, event: e }),
      ),
      // The month shows past days too: every meeting that hasn't ended, as the app's MySchedule.
      ...[...scheduleMeetings(feeds[t.id]?.meetings, false), ...(monthView ? scheduleMeetings(feeds[t.id]?.meetings, true) : [])].map(
        (m): Row => ({
          kind: "meeting",
          key: `${t.id}/meeting-${m.id}`,
          teamId: t.id,
          startsAt: m.startsAt,
          endsAt: m.endsAt,
          live: m.status === "live",
          team: t,
          meeting: m,
        }),
      ),
    ]),
  ];
  // Team entries stop where the calendars' window does, so the list has one horizon.
  const windowEnd = startOfToday().getTime() - dayMs + (calendarWindowDays - 1) * dayMs;
  const upcoming = upcomingSchedule(rows, { now: Date.now(), until: windowEnd, filter, hiddenCalendars: hidden });
  // The month view: each day's entries (the app's eventsOn), the picked day's week listed below the grid.
  const onDay = (d: Date) => scheduleOnDay(rows, d, { filter, hiddenCalendars: hidden });
  const pickedWeek = weekOf(picked);
  const pickedItems = onDay(picked);
  const weekCount = pickedWeek.reduce((n, d) => n + onDay(d).length, 0);
  const monthCount = grid.filter((d) => d.getMonth() === month.getMonth()).reduce((n, d) => n + onDay(d).length, 0);
  /** The dots on a day: team, personal, and one still to answer (DayMarks in the app). */
  function marksOn(d: Date) {
    const items = onDay(d);
    return {
      team: items.some((x) => x.kind !== "calendar"),
      personal: items.some((x) => x.kind === "calendar"),
      needs: items.some((x) =>
        x.kind === "event"
          ? needsRsvp(x.event.rsvps?.[me.uid], x.event.startsAt, x.event.endsAt)
          : x.kind === "meeting" && needsRsvp(meetingAnswer(x.meeting.rsvps?.[me.uid]), x.meeting.startsAt, x.meeting.endsAt),
      ),
    };
  }
  function chooseView(v: ScheduleView) {
    setView(v);
    saveView(v);
  }
  function moveMonth(by: number) {
    const next = new Date(month.getFullYear(), month.getMonth() + by, 1);
    setMonth(next);
    // Today when it's in that month, otherwise the 1st.
    setPicked(sameMonth(next, new Date()) ? startOfToday() : next);
  }
  function pickDay(d: Date) {
    setPicked(d);
    if (!sameMonth(d, month)) setMonth(firstOfMonth(d));
  }
  function moveWeek(by: number) {
    const next = new Date(picked.getFullYear(), picked.getMonth(), picked.getDate() + by * 7);
    setPicked(next);
    setMonth(firstOfMonth(next));
  }
  function goToToday() {
    setMonth(firstOfMonth(new Date()));
    setPicked(startOfToday());
  }
  const atToday = sameMonth(month, new Date()) && sameDay(picked, new Date());

  /** One entry on the list or under the picked day: an event card (C8), with its actions under it. */
  function renderRow(x: Row) {
    if (x.kind === "event") {
      const e = x.event;
      const label = eventTypeLabels[e.type as EventType] ?? "Event";
      const answer = e.rsvps?.[me.uid];
      return (
        <li key={x.key} className="sched-item">
          <EventCard
            startsAt={e.startsAt}
            title={e.title || label}
            href={`${teamBase(x.team.id)}/schedule?event=${encodeURIComponent(e.id)}`}
            meta={`${timeSpan(e.startsAt, e.endsAt)} · ${scheduleTeamLabel(x.team.name, teams.length)} · ${label}${e.location ? ` · ${e.location}` : ""}`}
            answer={answer}
            needsRsvp={needsRsvp(answer, e.startsAt, e.endsAt)}
            recurring={!!e.series}
          />
        </li>
      );
    }
    if (x.kind === "meeting") {
      const m = x.meeting;
      const answer = meetingAnswer(m.rsvps?.[me.uid]);
      return (
        <li key={x.key} className="sched-item">
          <EventCard
            startsAt={m.startsAt}
            title={m.title || "Meeting"}
            href={meetingHref(x.team.id, m.id)}
            meta={`${timeSpan(m.startsAt, m.endsAt)} · ${scheduleTeamLabel(x.team.name, teams.length)} · Meeting · ${x.live ? "Live now" : "Video meeting"}`}
            answer={answer}
            needsRsvp={needsRsvp(answer, m.startsAt, m.endsAt)}
          />
        </li>
      );
    }
    const e = x.event;
    const cal = byId.get(e.calendarId);
    return (
      <li key={x.key} className="sched-item">
        <EventCard
          startsAt={e.startsAt}
          title={e.title}
          meta={`${timeSpan(e.startsAt, e.endsAt)} · ${cal ? (cal.role === "owner" ? cal.name : `${cal.name} · ${cal.owner.name}`) : "Personal"} · ${eventTypeLabels[e.type]}${e.location ? ` · ${e.location}` : ""}`}
          recurring={!!e.series}
        />
        {e.notes && <small className="muted sched-notes">{e.notes}</small>}
        <span className="event-actions">
          {canEdit(cal) && (
            <>
              <button type="button" className="text-btn" onClick={() => setEditing(e)}>
                Edit
              </button>
              <button type="button" className="text-btn" onClick={() => void remove(e)}>
                Delete
              </button>
            </>
          )}
          <AddToCalendar
            event={{
              uid: `${e.calendarId}-${e.id}@stall10.app`,
              title: e.title,
              startsAt: e.startsAt,
              endsAt: e.endsAt,
              location: e.location,
              description: e.notes,
            }}
          />
        </span>
      </li>
    );
  }
  async function remove(e: CalendarEvent) {
    const which = e.series ? await scope.ask(`Delete "${e.title}"?`, "Delete") : (await askConfirm({ message: "Delete this event?", confirmLabel: "Delete", destructive: true })) ? "one" : null;
    if (!which) return;
    try {
      await callApi(me, `/v1/calendars/${encodeURIComponent(e.calendarId)}/events/${encodeURIComponent(e.id)}${scopeQuery(which)}`, {
        method: "DELETE",
      });
      await load();
    } catch (err) {
      window.alert(problem(err));
    }
  }

  return (
    <div className="stack schedule-page">
      {scope.dialog}
      {teams.map((t) => (
        <TeamFeed key={t.id} team={t} uid={me.uid} lookBack={feedLookBack} onData={onFeed} />
      ))}
      {data && data.invites.length > 0 && <Invites invites={data.invites} onAnswered={load} />}
      <div className="card sched-card">
        <div className="card-head">
          <h2 className="card-title">{weekView ? "Week" : monthView ? "Month" : "Upcoming"}</h2>
          <SegmentedTabs className="schedule-view" label="View" items={scheduleViews.map(([id, label]) => ({ id, label }))} value={view} onChange={(v) => chooseView(v as typeof view)} />
          {!editing && writable.length > 0 && (
            <Button variant="primary" size="small" onClick={() => setEditing({})}>
              Add event
            </Button>
          )}
        </div>
        <FilterChips className="schedule-filter" label="Show" items={scheduleFilters.map(([id, label]) => ({ id, label }))} value={filter} onChange={(f) => setFilter(f as typeof filter)} />
        {editing && data && (
          <EventEditor
            key={editing.id ?? "new"}
            event={editing}
            calendars={writable}
            onDone={(saved) => {
              setEditing(null);
              if (saved) void load();
            }}
          />
        )}
        {error && (
          <ErrorNote>
            {error}{" "}
            <button type="button" className="text-btn" onClick={() => void load()}>
              Retry
            </button>
          </ErrorNote>
        )}
        {monthView ? (
          <>
            <div className="sched-month-head">
              <button type="button" className="btn btn-small btn-quiet" aria-label={weekView ? "Previous week" : "Previous month"} onClick={() => (weekView ? moveWeek(-1) : moveMonth(-1))}>
                ‹
              </button>
              <p>
                <b>{weekView ? weekRangeLabel(pickedWeek) : month.toLocaleDateString(undefined, { month: "long", year: "numeric" })}</b>
                <small className="muted">
                  {weekView
                    ? `${weekCount === 1 ? "1 event" : `${weekCount} events`} this week`
                    : monthCount === 1
                      ? "1 event"
                      : `${monthCount} events`}
                </small>
              </p>
              <button type="button" className="btn btn-small btn-quiet" aria-label={weekView ? "Next week" : "Next month"} onClick={() => (weekView ? moveWeek(1) : moveMonth(1))}>
                ›
              </button>
              {!atToday && (
                <button type="button" className="text-btn" onClick={goToToday}>
                  Today
                </button>
              )}
            </div>
            <div className={`sched-month${weekView ? " week" : ""}`} role="grid" aria-label={weekView ? weekRangeLabel(pickedWeek) : month.toLocaleDateString(undefined, { month: "long", year: "numeric" })}>
              {["M", "T", "W", "T", "F", "S", "S"].map((d, i) => (
                <span key={i} className="sched-month-dow" aria-hidden>
                  {d}
                </span>
              ))}
              {(weekView ? pickedWeek : grid).map((d) => {
                const marks = marksOn(d);
                const today = sameDay(d, new Date());
                const on = sameDay(d, picked);
                return (
                  <button
                    key={d.getTime()}
                    type="button"
                    role="gridcell"
                    aria-selected={on}
                    aria-label={d.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}
                    className={`sched-month-day${!weekView && d.getMonth() !== month.getMonth() ? " out" : ""}${today ? " today" : ""}${on ? " on" : ""}`}
                    onClick={() => pickDay(d)}
                  >
                    <b>{d.getDate()}</b>
                    <span className="sched-month-dots" aria-hidden>
                      {marks.team && <i style={{ background: teamColor }} />}
                      {marks.personal && <i style={{ background: "var(--personal)" }} />}
                      {marks.needs && <i style={{ background: "var(--disc)" }} />}
                    </span>
                  </button>
                );
              })}
            </div>
            {/* The picked day's events. */}
            <section className="sched-day picked" aria-label={dayLabelOf(picked)}>
              <h3 className="sched-day-head">{dayLabelOf(picked)}</h3>
              {pickedItems.length === 0 ? <p className="muted small">Nothing scheduled</p> : <ul className="sched-list">{pickedItems.map(renderRow)}</ul>}
            </section>
          </>
        ) : !data && !error ? (
          <p className="muted">Loading…</p>
        ) : data && upcoming.length === 0 ? (
          <p className="muted small">
            {filter !== "team"
              ? "Nothing coming up. Add a workout, a pickup game or anything else you're doing."
              : teamsLive.data !== undefined && teams.length === 0
                ? "You're not on a team yet."
                : "Nothing coming up on your teams."}
          </p>
        ) : (
          <div className="sched-days">
            {byDay(upcoming).map(([day, items]) => (
              <section key={day} className="sched-day" aria-label={day}>
                <h3 className="sched-day-head">{day}</h3>
                <ul className="sched-list">
                  {items.map(renderRow)}
                </ul>
              </section>
            ))}
          </div>
        )}
      </div>
      {data && (
        <div className="card">
          <div className="card-head">
            <h2 className="card-title">Calendars</h2>
            <Link className="btn btn-small" href="/settings/calendar">
              Manage
            </Link>
          </div>
          <ul className="cal-list">
            {data.calendars.map((c) => (
              <li key={c.id}>
                <label className="cal-toggle">
                  <input
                    type="checkbox"
                    checked={!hidden.includes(c.id)}
                    onChange={() => toggle(c.id)}
                    style={{ accentColor: colorOf(c.color) }}
                  />
                  <span className="cal-dot" style={{ background: colorOf(c.color) }} aria-hidden />
                  <span>
                    {c.name}
                    {c.role !== "owner" && (
                      <small className="muted">
                        {" "}
                        · {c.owner.name} · {shareRoleLabels[c.role]}
                      </small>
                    )}
                  </span>
                </label>
              </li>
            ))}
          </ul>
          <p className="muted small">Share them or see them in Outlook, Apple or Google Calendar.</p>
        </div>
      )}
    </div>
  );
}

/** List or Month: how My schedule shows its days (the app's Week / Month). */
type ScheduleView = "list" | "week" | "month";
const scheduleViews: ReadonlyArray<readonly [ScheduleView, string]> = [
  ["month", "Month"],
  ["week", "Week"],
  ["list", "List"],
];
const viewKey = "stall10.schedule.view";

/** The view last picked in this browser (List when none, or storage is off). */
function loadView(): ScheduleView {
  try {
    const v = localStorage.getItem(viewKey);
    return v === "month" || v === "week" ? v : "list";
  } catch {
    return "list";
  }
}

function saveView(v: ScheduleView) {
  try {
    localStorage.setItem(viewKey, v);
  } catch {
    // The list next time; nothing else depends on it.
  }
}

const firstOfMonth = (d: Date) => new Date(d.getFullYear(), d.getMonth(), 1);
const sameMonth = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth();

/** The picked day's heading under the month: "Thursday, Nov 19", with Today when it is. */
function dayLabelOf(d: Date): string {
  const label = d.toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" });
  return sameDay(d, new Date()) ? `Today · ${label}` : label;
}

/** "Today", "Tomorrow" or "Sat, Nov 21": a day's heading on the list. */
function dayLabel(iso: string | null | undefined): string {
  const d = iso ? new Date(iso) : null;
  if (!d || Number.isNaN(d.getTime())) return "Later";
  const today = startOfToday().getTime();
  const day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  // An event under way since an earlier day is listed under today.
  if (day <= today) return "Today";
  if (day - today < 1.5 * dayMs) return "Tomorrow";
  return d.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
}

/** The list's entries under their days, soonest first (the order they came in). */
function byDay<T extends { startsAt?: string | null }>(items: T[]): Array<[string, T[]]> {
  const days: Array<[string, T[]]> = [];
  for (const x of items) {
    const label = dayLabel(x.startsAt);
    const last = days[days.length - 1];
    if (last && last[0] === label) last[1].push(x);
    else days.push([label, [x]]);
  }
  return days;
}

const timeOf = (d: Date) => d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });

/** "6:00 PM – 8:00 PM", or "6:00 PM – Nov 29" for one that ends another day, or just the start. */
function timeSpan(startsAt?: string, endsAt?: string | null): string {
  const start = startsAt ? new Date(startsAt) : null;
  if (!start || Number.isNaN(start.getTime())) return "";
  const end = endsAt ? new Date(endsAt) : null;
  if (!end || Number.isNaN(end.getTime())) return timeOf(start);
  return end.toDateString() === start.toDateString()
    ? `${timeOf(start)} – ${timeOf(end)}`
    : `${timeOf(start)} – ${end.toLocaleDateString(undefined, { month: "short", day: "numeric" })}`;
}

/** "Nov 23 – 29", or "Nov 30 – Dec 6" across a month. */
function weekRangeLabel(week: Date[]): string {
  const a = week[0];
  const b = week[week.length - 1];
  const from = a.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  const to = a.getMonth() === b.getMonth() ? String(b.getDate()) : b.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  return `${from} – ${to}`;
}

/** Invites waiting for the member: nothing is shared until they accept. */
export function Invites({ invites, onAnswered }: { invites: CalendarInvite[]; onAnswered: () => void | Promise<void> }) {
  const { user } = useAuth();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  if (!user) return null;
  const me = user;

  async function answer(id: string, how: "accept" | "decline") {
    setBusy(id);
    setError(null);
    try {
      await callApi(me, `/v1/me/calendar-invites/${encodeURIComponent(id)}/${how}`, { method: "POST" });
      await onAnswered();
    } catch (e) {
      setError(problem(e));
      await onAnswered();
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="card cal-invites">
      <h2 className="card-title">Calendar invites</h2>
      <ul className="person-list">
        {invites.map((i) => (
          <li key={i.calendarId} className="person-row">
            <span className="cal-dot" style={{ background: colorOf(i.color) }} aria-hidden />
            <span>
              <b>{i.from.name}</b> invited you to <b>{i.calendarName}</b>
              <small className="muted"> · {shareRoleLabels[i.role]}</small>
            </span>
            <button
              type="button"
              className="btn btn-primary btn-small"
              disabled={busy !== null}
              onClick={() => void answer(i.calendarId, "accept")}
            >
              Accept
            </button>
            <button
              type="button"
              className="btn btn-small"
              disabled={busy !== null}
              onClick={() => void answer(i.calendarId, "decline")}
            >
              Decline
            </button>
          </li>
        ))}
      </ul>
      {error && <ErrorNote>{error}</ErrorNote>}
    </div>
  );
}

/**
 * Adding or changing an event, on any calendar the member may change. Its
 * types are the app's for a personal schedule (no pickup, which groups run).
 * An existing event stays on its calendar.
 */
function EventEditor({
  event,
  calendars,
  onDone,
}: {
  event: Partial<CalendarEvent> & { calendarId?: string };
  calendars: CalendarInfo[];
  onDone: (saved: boolean) => void;
}) {
  const { user } = useAuth();
  // Calendars made here (New shared calendar) join the list at once.
  const [made, setMade] = useState<CalendarInfo[]>([]);
  const [newCal, setNewCal] = useState(false);
  const [calendarId, setCalendarId] = useState(event.calendarId ?? calendars[0]?.id ?? "");
  const [title, setTitle] = useState(event.title ?? "");
  const [type, setType] = useState<EventType>(event.type ?? "workout");
  const [startsAt, setStartsAt] = useState(toLocalInput(event.startsAt));
  const [endsAt, setEndsAt] = useState(toLocalInput(event.endsAt));
  const [location, setLocation] = useState(event.location ?? "");
  const [notes, setNotes] = useState(event.notes ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // A new event may be posted for followers, as the app's editor offers on
  // My calendar and shared calendars (canShare); the list only offers
  // calendars the member can edit.
  const canShare = !event.id;
  const [share, setShare] = useState<ShareChoice>({ on: false, message: "" });
  // A new event may repeat; an event of a series asks "this or following" on save.
  const [repeat, setRepeat] = useState<Repeat | null>(null);
  const scope = useSeriesScope();
  if (!user) return null;
  const me = user;
  const all = [...calendars, ...made.filter((m) => !calendars.some((c) => c.id === m.id))];
  const calendar = all.find((c) => c.id === calendarId);

  async function save(e: FormEvent) {
    e.preventDefault();
    const start = fromLocalInput(startsAt);
    if (!start) return setError("Pick when it starts.");
    const end = fromLocalInput(endsAt);
    if (end && Date.parse(end) < Date.parse(start)) return setError("It can't end before it starts.");
    if (!calendarId) return setError("Pick a calendar.");
    const rule = event.id ? null : repeat;
    const bad = repeatFormProblem(startsAt, rule);
    if (bad) return setError(bad);
    const which = event.series ? await scope.ask(`Save changes to "${title.trim()}"?`, "Save") : "one";
    if (!which) return;
    setBusy(true);
    setError(null);
    const body = {
      title,
      type,
      startsAt: start,
      endsAt: end,
      location,
      notes,
      ...(rule && { repeat: rule }),
      ...((rule || which === "following") && { timeZone: browserTimeZone() }),
    };
    const base = `/v1/calendars/${encodeURIComponent(calendarId)}/events`;
    try {
      if (event.id) {
        await callApi(me, `${base}/${encodeURIComponent(event.id)}${scopeQuery(which)}`, { method: "PATCH", body });
      } else {
        const res = await callApi<CalendarEventResult>(me, base, { method: "POST", body });
        // The event is saved either way, as in the app and TeamEventEditor.
        if (canShare && share.on && !(await shareEvent(me, null, res.id, share.message, calendarId))) {
          window.alert("Event created, but it couldn't be shared. Try posting it.");
        }
      }
      onDone(true);
    } catch (err) {
      setError(problem(err));
      setBusy(false);
    }
  }

  const shared = calendar ? calendar.role !== "owner" || (calendar.members?.length ?? 1) > 1 : false;
  return (
    <form className="settings-form event-editor" onSubmit={(e) => void save(e)}>
      {scope.dialog}
      <label>
        Calendar
        <select
          value={calendarId}
          disabled={Boolean(event.id)}
          onChange={(e) => (e.target.value === NEW_CALENDAR ? setNewCal(true) : setCalendarId(e.target.value))}
        >
          {all.map((c) => (
            <option key={c.id} value={c.id}>
              {c.role === "owner" ? c.name : `${c.name} (${c.owner.name})`}
            </option>
          ))}
          {!event.id && <option value={NEW_CALENDAR}>New shared calendar…</option>}
        </select>
      </label>
      {newCal && (
        <NewSharedCalendar
          me={me}
          onCancel={() => setNewCal(false)}
          onMade={(c) => {
            setMade((m) => [...m, c]);
            setCalendarId(c.id);
            setNewCal(false);
          }}
        />
      )}
      <label>
        Title
        <input value={title} required maxLength={100} onChange={(e) => setTitle(e.target.value)} />
      </label>
      <label>
        Type
        <select value={type} onChange={(e) => setType(e.target.value as EventType)}>
          {[...calendarEventTypes, ...(event.type === "pickup" ? (["pickup"] as const) : [])].map((t) => (
            <option key={t} value={t}>
              {eventTypeLabels[t]}
            </option>
          ))}
        </select>
      </label>
      <div className="form-row">
        <label>
          Starts
          <input type="datetime-local" required value={startsAt} onChange={(e) => setStartsAt(e.target.value)} />
        </label>
        <label>
          Ends <small className="muted">(optional)</small>
          <input type="datetime-local" value={endsAt} min={startsAt} onChange={(e) => setEndsAt(e.target.value)} />
        </label>
      </div>
      {event.id ? event.series && <RepeatNote series={event.series} /> : <RepeatField startsAt={startsAt} value={repeat} onChange={setRepeat} />}
      <label>
        Where <small className="muted">(optional)</small>
        <input value={location} maxLength={200} onChange={(e) => setLocation(e.target.value)} />
      </label>
      <label>
        Notes{" "}
        <small className="muted">
          {shared ? "(people who can edit this calendar see these; viewers don't)" : "(only you see these)"}
        </small>
        <textarea value={notes} rows={3} maxLength={5000} onChange={(e) => setNotes(e.target.value)} />
      </label>
      {canShare && <ShareEventField value={share} onChange={setShare} personal />}
      <div className="form-actions">
        {error && (
          <span className="form-error" role="alert">
            {error}
          </span>
        )}
        <button type="button" className="btn" disabled={busy} onClick={() => onDone(false)}>
          Cancel
        </button>
        <button type="submit" className="btn btn-primary" disabled={busy}>
          {busy ? "Saving…" : event.id ? "Save" : "Add"}
        </button>
      </div>
    </form>
  );
}

const NEW_CALENDAR = "__new";

/**
 * From the event editor: a calendar to share, made on the spot (name,
 * color, who to invite and what they may do), so sharing an event needs no
 * trip to Calendars first. As the app's New shared calendar sheet.
 */
function NewSharedCalendar({
  me,
  onMade,
  onCancel,
}: {
  me: NonNullable<ReturnType<typeof useAuth>["user"]>;
  onMade: (c: CalendarInfo) => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState("");
  const [color, setColor] = useState<CalendarColor>("blue");
  const [role, setRole] = useState<ShareRole>("view");
  const [people, setPeople] = useState<PickedPerson[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function create() {
    if (!name.trim()) return setError("Name the calendar.");
    setBusy(true);
    setError(null);
    try {
      const cal = await callApi<CalendarInfo>(me, "/v1/me/calendars", { method: "POST", body: { name: name.trim(), color } });
      let missed = 0;
      for (const p of people) {
        try {
          await callApi(me, `/v1/calendars/${encodeURIComponent(cal.id)}/invites`, { method: "POST", body: { uid: p.uid, role } });
        } catch {
          missed++;
        }
      }
      if (missed > 0) window.alert(`${cal.name} is made, but ${missed} invite${missed === 1 ? "" : "s"} didn't send. Invite them from Calendars.`);
      onMade(cal);
    } catch (err) {
      setError(problem(err));
      setBusy(false);
    }
  }

  return (
    <fieldset className="new-shared-cal">
      <legend>New shared calendar</legend>
      <p className="muted small">This event goes on it. People see it once they accept; add more later from Calendars.</p>
      <label>
        Name
        <input value={name} maxLength={60} placeholder="e.g. Family, Carpool" autoFocus onChange={(e) => setName(e.target.value)} />
      </label>
      <ColorPicker value={color} onChange={setColor} disabled={busy} />
      <label>
        They can
        <select value={role} disabled={busy} onChange={(e) => setRole(e.target.value as ShareRole)}>
          {shareRoles.map((r) => (
            <option key={r} value={r}>
              {shareRoleLabels[r]}
            </option>
          ))}
        </select>
      </label>
      {people.length > 0 && (
        <ul className="chip-list">
          {people.map((p) => (
            <li key={p.uid}>
              {p.name}{" "}
              <button type="button" className="text-btn" aria-label={`Remove ${p.name}`} onClick={() => setPeople(people.filter((x) => x.uid !== p.uid))}>
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
      <PersonPicker
        label="Invite people by name or username"
        exclude={[me.uid, ...people.map((p) => p.uid)]}
        disabled={busy}
        onPick={(p) => setPeople((x) => [...x, p])}
      />
      <div className="form-actions">
        {error && (
          <span className="form-error" role="alert">
            {error}
          </span>
        )}
        <button type="button" className="btn" disabled={busy} onClick={onCancel}>
          Cancel
        </button>
        <button type="button" className="btn btn-primary" disabled={busy || !name.trim()} onClick={() => void create()}>
          {busy ? "Creating…" : people.length ? "Create and invite" : "Create calendar"}
        </button>
      </div>
    </fieldset>
  );
}
