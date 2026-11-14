"use client";
import {
  type EventType,
  eventTypeLabels,
  eventTypes,
  type PersonalEventResult,
  type SharedCalendarsResponse,
} from "@stall10/shared";
import { limit, orderBy, Timestamp, where } from "firebase/firestore";
import Link from "next/link";
import { type FormEvent, useCallback, useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useLiveQuery } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { EventItem } from "./EventItem";
import { LocalTime } from "./LocalTime";

/** A personal event as stored (users/{uid}/events; TeamEvent in the app). */
interface MyEvent {
  title?: string;
  type?: EventType;
  startsAt?: string;
  endsAt?: string | null;
  location?: string;
  notes?: string;
}

const dayMs = 86_400_000;
/** How far ahead shared calendars are shown. */
const sharedDays = 30;
const problem = (e: unknown) => (e instanceof ApiError ? e.message : "Something went wrong. Try again.");

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

/**
 * The member's own schedule on the website: their personal events (read
 * live; written through the API, as validMine allows) and the calendars
 * others share with them (read-only, through the API). Team events stay on
 * each team's page.
 */
export function Schedule() {
  const { user } = useAuth();
  const [since] = useState(() => startOfToday() - dayMs);
  const { data: mine, error } = useLiveQuery<MyEvent>(
    user ? `users/${user.uid}/events` : null,
    [where("startsAt", ">=", Timestamp.fromMillis(since)), orderBy("startsAt"), limit(200)],
    `mine-${since}`,
  );
  const [editing, setEditing] = useState<(MyEvent & { id?: string }) | null>(null);

  if (!user) return null;
  const upcoming = (mine ?? []).filter((e) => {
    const end = Date.parse(e.endsAt ?? e.startsAt ?? "");
    return Number.isFinite(end) && end >= Date.now() - 60 * 60_000;
  });

  return (
    <div className="stack">
      <div className="card">
        <div className="card-head">
          <h2 className="card-title">Your events</h2>
          {!editing && (
            <button type="button" className="btn btn-primary btn-small" onClick={() => setEditing({})}>
              Add event
            </button>
          )}
        </div>
        {editing && <EventEditor key={editing.id ?? "new"} event={editing} onDone={() => setEditing(null)} />}
        {error && <p className="form-error">{error}</p>}
        {mine === undefined && !error ? (
          <p className="muted">Loading…</p>
        ) : upcoming.length === 0 ? (
          <p className="muted small">Nothing coming up. Add a workout, a pickup game or anything else you&apos;re doing.</p>
        ) : (
          <div className="stack">
            {upcoming.map((e) => (
              <EventItem key={e.id} startsAt={e.startsAt}>
                <b>{e.title || "Event"}</b>
                <small>
                  {eventTypeLabels[e.type ?? "other"] ?? "Event"} · <LocalTime iso={e.startsAt} style="dateTime" />
                  {e.location ? ` · ${e.location}` : ""}
                </small>
                {e.notes && <small className="muted">{e.notes}</small>}
                <span className="event-actions">
                  <button type="button" className="text-btn" onClick={() => setEditing(e)}>
                    Edit
                  </button>
                  <DeleteButton id={e.id} />
                </span>
              </EventItem>
            ))}
          </div>
        )}
        <p className="muted small">
          <Link href="/settings/calendar">Share your calendar</Link> with friends, a coach or family.
        </p>
      </div>
      <SharedCalendars />
    </div>
  );
}

function DeleteButton({ id }: { id: string }) {
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  if (!user) return null;
  const me = user;
  return (
    <button
      type="button"
      className="text-btn"
      disabled={busy}
      onClick={async () => {
        if (!window.confirm("Delete this event?")) return;
        setBusy(true);
        try {
          await callApi(me, `/v1/me/events/${encodeURIComponent(id)}`, { method: "DELETE" });
        } catch (e) {
          window.alert(problem(e));
          setBusy(false);
        }
      }}
    >
      Delete
    </button>
  );
}

/**
 * Adding or changing a personal event. Its types are the app's for a
 * personal schedule (EventType.editableFor(community: false)): no pickup,
 * which groups run.
 */
function EventEditor({ event, onDone }: { event: MyEvent & { id?: string }; onDone: () => void }) {
  const { user } = useAuth();
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

  async function save(e: FormEvent) {
    e.preventDefault();
    const start = fromLocalInput(startsAt);
    if (!start) return setError("Pick when it starts.");
    const end = fromLocalInput(endsAt);
    if (end && Date.parse(end) < Date.parse(start)) return setError("It can't end before it starts.");
    setBusy(true);
    setError(null);
    const body = { title, type, startsAt: start, endsAt: end, location, notes };
    try {
      if (event.id) {
        await callApi(me, `/v1/me/events/${encodeURIComponent(event.id)}`, { method: "PATCH", body });
      } else {
        await callApi<PersonalEventResult>(me, "/v1/me/events", { method: "POST", body });
      }
      onDone();
    } catch (err) {
      setError(problem(err));
      setBusy(false);
    }
  }

  return (
    <form className="settings-form event-editor" onSubmit={(e) => void save(e)}>
      <label>
        Title
        <input value={title} required maxLength={100} onChange={(e) => setTitle(e.target.value)} />
      </label>
      <label>
        Type
        <select value={type} onChange={(e) => setType(e.target.value as EventType)}>
          {eventTypes.filter((t) => t !== "pickup" || t === event.type).map((t) => (
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
        Notes <small className="muted">(only you see these)</small>
        <textarea value={notes} rows={3} maxLength={5000} onChange={(e) => setNotes(e.target.value)} />
      </label>
      <div className="form-actions">
        {error && (
          <span className="form-error" role="alert">
            {error}
          </span>
        )}
        <button type="button" className="btn" disabled={busy} onClick={onDone}>
          Cancel
        </button>
        <button type="submit" className="btn btn-primary" disabled={busy}>
          {busy ? "Saving…" : event.id ? "Save" : "Add"}
        </button>
      </div>
    </form>
  );
}

/** Calendars others share with the member: the next 30 days, read-only. */
function SharedCalendars() {
  const { user } = useAuth();
  const [data, setData] = useState<SharedCalendarsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    const from = startOfToday();
    const qs = new URLSearchParams({
      from: new Date(from).toISOString(),
      to: new Date(from + sharedDays * dayMs).toISOString(),
    });
    try {
      setData(await callApi<SharedCalendarsResponse>(user, `/v1/me/calendar/shared?${qs}`));
      setError(null);
    } catch (e) {
      setError(problem(e));
    }
  }, [user]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!data && !error) return null;
  if (data && data.calendars.length === 0) return null;
  return (
    <div className="card">
      <h2 className="card-title">Shared with you</h2>
      {error && (
        <p className="form-error">
          {error}{" "}
          <button type="button" className="text-btn" onClick={() => void load()}>
            Retry
          </button>
        </p>
      )}
      {data?.calendars.map(({ owner, events }) => (
        <section key={owner.uid} className="shared-calendar">
          <h3 className="shared-calendar-owner">
            <Avatar name={owner.name} url={owner.photoUrl ?? undefined} size={28} />
            <Link href={`/players/${encodeURIComponent(owner.uid)}`}>{owner.name}</Link>
          </h3>
          {events.length === 0 ? (
            <p className="muted small">Nothing in the next {sharedDays} days.</p>
          ) : (
            <div className="stack">
              {events.map((e) => (
                <EventItem key={e.id} startsAt={e.startsAt}>
                  <b>{e.title}</b>
                  <small>
                    {eventTypeLabels[e.type]} · <LocalTime iso={e.startsAt} style="dateTime" />
                    {e.location ? ` · ${e.location}` : ""}
                  </small>
                </EventItem>
              ))}
            </div>
          )}
        </section>
      ))}
    </div>
  );
}
