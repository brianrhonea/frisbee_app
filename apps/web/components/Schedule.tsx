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
  shareRoleLabels,
} from "@stall10/shared";
import Link from "next/link";
import { type FormEvent, useCallback, useEffect, useState } from "react";
import { colorOf, downloadIcs, loadHidden, saveHidden } from "@/lib/calendar";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "./AuthProvider";
import { EventItem } from "./EventItem";
import { LocalTime } from "./LocalTime";

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

/**
 * The member's schedule on the website, like Outlook or Apple Calendar:
 * every calendar they're on (their own and ones they accepted), each in
 * its color and hidden or shown on this browser, with invites to accept.
 * Events are added to any calendar they may change. Everything goes through
 * the API, which checks each calendar's members. Team events stay on each
 * team's page.
 */
export function Schedule() {
  const { user } = useAuth();
  const [data, setData] = useState<Loaded | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [hidden, setHidden] = useState<string[]>([]);
  const [editing, setEditing] = useState<(Partial<CalendarEvent> & { calendarId?: string }) | null>(null);

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
  const upcoming = (data?.events ?? []).filter((e) => {
    if (hidden.includes(e.calendarId)) return false;
    const end = Date.parse(e.endsAt ?? e.startsAt);
    return Number.isFinite(end) && end >= Date.now() - 60 * 60_000;
  });

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
          <p className="muted small">Nothing coming up. Add a workout, a pickup game or anything else you&apos;re doing.</p>
        ) : (
          <div className="stack">
            {upcoming.map((e) => {
              const cal = byId.get(e.calendarId);
              return (
                <EventItem key={`${e.calendarId}/${e.id}`} startsAt={e.startsAt}>
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
        await callApi<CalendarEventResult>(me, base, { method: "POST", body });
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
