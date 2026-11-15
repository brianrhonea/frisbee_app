"use client";
import {
  type CalendarEvent,
  type CalendarEventResult,
  type CalendarEventsResponse,
  type CalendarInfo,
  type CalendarInvite,
  type CalendarInvitesResponse,
  type CalendarsResponse,
  calendarEventTypes,
  calendarWindowDays,
  type EventType,
  eventTypeLabels,
  type ScheduleFilter,
  type ScheduleItem,
  scheduleFilters,
  scheduleTeamLabel,
  shareRoleLabels,
  upcomingSchedule,
} from "@stall10/shared";
import { where } from "firebase/firestore";
import Link from "next/link";
import { type FormEvent, useCallback, useEffect, useState } from "react";
import { colorOf, downloadIcs, loadHidden, saveHidden } from "@/lib/calendar";
import { ApiError, callApi } from "@/lib/client";
import { type Doc, useLiveQueries, useLiveQuery } from "@/lib/live";
import { type Meeting, type MeetingData, meetingHref, teamBase, teamMeetingQueries } from "./team/meetings/model";
import { memberViewer, type TeamDoc } from "./team/TeamContext";
import { scheduleMeetings, type TeamEventDoc, teamEventQueries } from "./team/TeamSchedule";
import { useAuth } from "./AuthProvider";
import { EventItem } from "./EventItem";
import { LocalTime } from "./LocalTime";
import { type ShareChoice, ShareEventField, shareEvent } from "./team/ShareEvent";

const dayMs = 86_400_000;
const problem = (e: unknown) => (e instanceof ApiError ? e.message : "Something went wrong. Try again.");
const canEdit = (c: CalendarInfo | undefined) => c?.role === "owner" || c?.role === "edit";

/** ISO → the value a datetime-local input takes, in the browser's zone. */
function toLocalInput(iso?: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
}
const fromLocalInput = (v: string) => (v ? new Date(v).toISOString() : null);

function startOfToday(): number {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

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
const teamColor = "var(--accent)";

/**
 * Listens to one team's upcoming events and meetings for My schedule, with
 * the same reads (and so the same rules) as the team's own schedule, and
 * hands them up. Renders nothing. A refused or failed read leaves that
 * team out rather than blanking the schedule, as MySchedule logs and goes on.
 */
function TeamFeed({
  team,
  uid,
  onData,
}: {
  team: Doc<TeamDoc>;
  uid: string;
  onData: (teamId: string, data: TeamFeedData | null) => void;
}) {
  const member = memberViewer(team, uid);
  const ev = teamEventQueries(member, false, lookBackDays);
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
  const { user } = useAuth();
  const [data, setData] = useState<Loaded | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [hidden, setHidden] = useState<string[]>([]);
  const [editing, setEditing] = useState<(Partial<CalendarEvent> & { calendarId?: string }) | null>(null);
  const [filter, setFilter] = useState<ScheduleFilter>("all");
  // Every team the member is on (watchMyTeams), each listened to by a TeamFeed.
  const teamsLive = useLiveQuery<TeamDoc>(
    user ? "teams" : null,
    user ? [where("memberIds", "array-contains", user.uid)] : [],
    user?.uid ?? "",
  );
  const [feeds, setFeeds] = useState<Record<string, TeamFeedData>>({});
  const onFeed = useCallback((teamId: string, d: TeamFeedData | null) => {
    setFeeds((f) => {
      if (d) return { ...f, [teamId]: d };
      const next = { ...f };
      delete next[teamId];
      return next;
    });
  }, []);

  useEffect(() => setHidden(loadHidden()), []);

  const load = useCallback(async () => {
    if (!user) return;
    const from = startOfToday() - dayMs;
    const qs = new URLSearchParams({
      from: new Date(from).toISOString(),
      to: new Date(from + (calendarWindowDays - 1) * dayMs).toISOString(),
    });
    try {
      const [c, i, e] = await Promise.all([
        callApi<CalendarsResponse>(user, "/v1/me/calendars"),
        callApi<CalendarInvitesResponse>(user, "/v1/me/calendar-invites"),
        callApi<CalendarEventsResponse>(user, `/v1/me/calendar-events?${qs}`),
      ]);
      setData({ calendars: c.calendars, invites: i.invites, events: e.events });
      setError(null);
    } catch (err) {
      setError(problem(err));
    }
  }, [user]);

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
      ...scheduleMeetings(feeds[t.id]?.meetings, false).map(
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
  const windowEnd = startOfToday() - dayMs + (calendarWindowDays - 1) * dayMs;
  const upcoming = upcomingSchedule(rows, { now: Date.now(), until: windowEnd, filter, hiddenCalendars: hidden });

  /** Team events can be deleted from here by the team's event managers, as the app's swipe does. */
  async function removeTeamEvent(team: Doc<TeamDoc>, e: Doc<TeamEventDoc>) {
    if (!window.confirm("Delete this event for everyone?")) return;
    try {
      // The listener drops it once it's gone.
      await callApi(me, `/v1/teams/${encodeURIComponent(team.id)}/events/${encodeURIComponent(e.id)}`, {
        method: "DELETE",
      });
    } catch (err) {
      window.alert(problem(err));
    }
  }

  async function remove(e: CalendarEvent) {
    if (!window.confirm("Delete this event?")) return;
    try {
      await callApi(me, `/v1/calendars/${encodeURIComponent(e.calendarId)}/events/${encodeURIComponent(e.id)}`, {
        method: "DELETE",
      });
      await load();
    } catch (err) {
      window.alert(problem(err));
    }
  }

  return (
    <div className="stack">
      {teams.map((t) => (
        <TeamFeed key={t.id} team={t} uid={me.uid} onData={onFeed} />
      ))}
      {data && data.invites.length > 0 && <Invites invites={data.invites} onAnswered={load} />}
      <div className="card">
        <div className="card-head">
          <h2 className="card-title">Upcoming</h2>
          {!editing && writable.length > 0 && (
            <button type="button" className="btn btn-primary btn-small" onClick={() => setEditing({})}>
              Add event
            </button>
          )}
        </div>
        <div className="segmented schedule-filter" role="tablist" aria-label="Show">
          {scheduleFilters.map(([f, label]) => (
            <button
              key={f}
              type="button"
              role="tab"
              aria-selected={filter === f}
              className={filter === f ? "on" : ""}
              onClick={() => setFilter(f)}
            >
              {label}
            </button>
          ))}
        </div>
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
          <p className="form-error">
            {error}{" "}
            <button type="button" className="text-btn" onClick={() => void load()}>
              Retry
            </button>
          </p>
        )}
        {!data && !error ? (
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
          <div className="stack">
            {upcoming.map((x) => {
              if (x.kind === "event") {
                const e = x.event;
                const label = eventTypeLabels[e.type as EventType] ?? "Event";
                return (
                  <EventItem key={x.key} startsAt={e.startsAt}>
                    <b>
                      <span className="cal-dot" style={{ background: teamColor }} aria-hidden />
                      <Link href={`${teamBase(x.team.id)}/schedule?event=${encodeURIComponent(e.id)}`}>{e.title || label}</Link>
                    </b>
                    <small>
                      {label} · <LocalTime iso={e.startsAt} style="dateTime" />
                      {e.location ? ` · ${e.location}` : ""}
                    </small>
                    <small className="muted">{scheduleTeamLabel(x.team.name, teams.length)}</small>
                    {memberViewer(x.team, me.uid).can("manageEvents") && (
                      <span className="event-actions">
                        <button type="button" className="text-btn danger" onClick={() => void removeTeamEvent(x.team, e)}>
                          Delete
                        </button>
                      </span>
                    )}
                  </EventItem>
                );
              }
              if (x.kind === "meeting") {
                const m = x.meeting;
                return (
                  <EventItem key={x.key} startsAt={m.startsAt}>
                    <b>
                      <span className="cal-dot" style={{ background: teamColor }} aria-hidden />
                      <Link href={meetingHref(x.team.id, m.id)}>{m.title || "Meeting"}</Link>
                    </b>
                    <small>
                      Meeting · <LocalTime iso={m.startsAt} style="dateTime" /> ·{" "}
                      <span className={x.live ? "schedule-meeting-live" : ""}>{x.live ? "Live now" : "Video meeting"}</span>
                    </small>
                    <small className="muted">{scheduleTeamLabel(x.team.name, teams.length)}</small>
                  </EventItem>
                );
              }
              const e = x.event;
              const cal = byId.get(e.calendarId);
              return (
                <EventItem key={x.key} startsAt={e.startsAt}>
                  <b>
                    <span className="cal-dot" style={{ background: colorOf(cal?.color) }} aria-hidden />
                    {e.title}
                  </b>
                  <small>
                    {eventTypeLabels[e.type]} · <LocalTime iso={e.startsAt} style="dateTime" />
                    {e.location ? ` · ${e.location}` : ""}
                  </small>
                  <small className="muted">
                    {cal ? (cal.role === "owner" ? cal.name : `${cal.name} · ${cal.owner.name}`) : ""}
                  </small>
                  {e.notes && <small className="muted">{e.notes}</small>}
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
                    <button
                      type="button"
                      className="text-btn"
                      onClick={() =>
                        downloadIcs({
                          uid: `${e.calendarId}-${e.id}@stall10.app`,
                          title: e.title,
                          startsAt: e.startsAt,
                          endsAt: e.endsAt,
                          location: e.location,
                          description: e.notes,
                        })
                      }
                    >
                      Add to calendar
                    </button>
                  </span>
                </EventItem>
              );
            })}
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
          <p className="muted small">
            <Link href="/settings/calendar">Share a calendar</Link> with friends, a coach or family, or{" "}
            <Link href="/settings/calendar#subscribe">see it in Outlook, Apple or Google Calendar</Link>.
          </p>
        </div>
      )}
    </div>
  );
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
      {error && <p className="form-error">{error}</p>}
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
  if (!user) return null;
  const me = user;
  const calendar = calendars.find((c) => c.id === calendarId);

  async function save(e: FormEvent) {
    e.preventDefault();
    const start = fromLocalInput(startsAt);
    if (!start) return setError("Pick when it starts.");
    const end = fromLocalInput(endsAt);
    if (end && Date.parse(end) < Date.parse(start)) return setError("It can't end before it starts.");
    if (!calendarId) return setError("Pick a calendar.");
    setBusy(true);
    setError(null);
    const body = { title, type, startsAt: start, endsAt: end, location, notes };
    const base = `/v1/calendars/${encodeURIComponent(calendarId)}/events`;
    try {
      if (event.id) {
        await callApi(me, `${base}/${encodeURIComponent(event.id)}`, { method: "PATCH", body });
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
      <label>
        Calendar
        <select value={calendarId} disabled={Boolean(event.id)} onChange={(e) => setCalendarId(e.target.value)}>
          {calendars.map((c) => (
            <option key={c.id} value={c.id}>
              {c.role === "owner" ? c.name : `${c.name} (${c.owner.name})`}
            </option>
          ))}
        </select>
      </label>
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
