"use client";
import {
  type CalendarColor,
  type CalendarFeedResponse,
  type CalendarInfo,
  type CalendarInvitesResponse,
  type CalendarsResponse,
  calendarColors,
  calendarNameMax,
  calendarPeopleMax,
  type ShareRole,
  shareRoleLabels,
  shareRoles,
} from "@stall10/shared";
import Link from "next/link";
import { type FormEvent, useCallback, useEffect, useState } from "react";
import { colorOf } from "@/lib/calendar";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { PersonPicker } from "../PersonPicker";
import { Invites } from "../Schedule";

const problem = (e: unknown) => (e instanceof ApiError ? e.message : "Something went wrong. Try again.");
const colorName = (c: CalendarColor) => c[0]!.toUpperCase() + c.slice(1);

type Call = (path: string, init?: { method?: string; body?: unknown }) => Promise<void>;

/**
 * Settings → Calendars, as in Outlook or Apple Calendar: the member's
 * calendars (name, color, and who's on each as Can view or Can edit),
 * invites to accept, calendars shared with them, and a private link that
 * keeps Outlook, Apple or Google Calendar in step. Inviting someone shares
 * nothing until they accept.
 */
export function CalendarSettings() {
  const { user } = useAuth();
  const [calendars, setCalendars] = useState<CalendarInfo[] | null>(null);
  const [invites, setInvites] = useState<CalendarInvitesResponse["invites"]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    if (!user) return;
    try {
      const [c, i] = await Promise.all([
        callApi<CalendarsResponse>(user, "/v1/me/calendars"),
        callApi<CalendarInvitesResponse>(user, "/v1/me/calendar-invites"),
      ]);
      setCalendars(c.calendars);
      setInvites(i.invites);
      setError(null);
    } catch (e) {
      setError(problem(e));
    }
  }, [user]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!user) return null;
  const me = user;

  /** Runs one change, then reloads; its problem shows at the top. */
  const run: Call = async (path, init) => {
    setBusy(true);
    setError(null);
    try {
      await callApi(me, path, init);
    } catch (e) {
      setError(problem(e));
    } finally {
      await load();
      setBusy(false);
    }
  };

  const mine = (calendars ?? []).filter((c) => c.role === "owner");
  const shared = (calendars ?? []).filter((c) => c.role !== "owner");

  return (
    <div className="stack">
      {invites.length > 0 && <Invites invites={invites} onAnswered={load} />}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {calendars === null ? (
        !error && <p className="muted">Loading…</p>
      ) : (
        <>
          {mine.map((c) => (
            <OwnedCalendar key={c.id} calendar={c} busy={busy} run={run} />
          ))}
          <NewCalendar busy={busy} run={run} />
          {shared.length > 0 && (
            <div className="card">
              <h2 className="card-title">Shared with you</h2>
              <ul className="person-list">
                {shared.map((c) => (
                  <li key={c.id} className="person-row">
                    <span className="cal-dot" style={{ background: colorOf(c.color) }} aria-hidden />
                    <span>
                      <b>{c.name}</b>
                      <small className="muted">
                        {" "}
                        · {c.owner.name} · {shareRoleLabels[c.role as ShareRole]}
                      </small>
                    </span>
                    <button
                      type="button"
                      className="btn btn-small"
                      disabled={busy}
                      onClick={() => {
                        if (!window.confirm(`Leave "${c.name}"? You'll need a new invite to see it again.`)) return;
                        void run(`/v1/calendars/${encodeURIComponent(c.id)}/members/${encodeURIComponent(me.uid)}`, {
                          method: "DELETE",
                        });
                      }}
                    >
                      Leave
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </>
      )}
      <Subscribe />
      <p className="muted small">
        <Link href="/schedule">Your schedule</Link>
      </p>
    </div>
  );
}

function ColorPicker({ value, onChange, disabled }: { value: CalendarColor; onChange: (c: CalendarColor) => void; disabled?: boolean }) {
  return (
    <div className="cal-colors" role="radiogroup" aria-label="Color">
      {calendarColors.map((c) => (
        <button
          key={c}
          type="button"
          role="radio"
          aria-checked={value === c}
          aria-label={colorName(c)}
          title={colorName(c)}
          disabled={disabled}
          className={`cal-swatch${value === c ? " selected" : ""}`}
          style={{ background: colorOf(c) }}
          onClick={() => onChange(c)}
        />
      ))}
    </div>
  );
}

function OwnedCalendar({ calendar: c, busy, run }: { calendar: CalendarInfo; busy: boolean; run: Call }) {
  const [name, setName] = useState(c.name);
  const [role, setRole] = useState<ShareRole>("view");
  const path = `/v1/calendars/${encodeURIComponent(c.id)}`;
  const members = (c.members ?? []).filter((m) => m.role !== "owner");
  const pending = c.pending ?? [];
  const people = members.length + pending.length + 1;

  function rename(e: FormEvent) {
    e.preventDefault();
    if (name.trim() && name.trim() !== c.name) void run(path, { method: "PATCH", body: { name } });
  }

  return (
    <div className="card">
      <div className="card-head">
        <h2 className="card-title">
          <span className="cal-dot" style={{ background: colorOf(c.color) }} aria-hidden />
          {c.name}
        </h2>
        {!c.isDefault && (
          <button
            type="button"
            className="btn btn-small"
            disabled={busy}
            onClick={() => {
              if (!window.confirm(`Delete "${c.name}" and all its events? Everyone on it loses it.`)) return;
              void run(path, { method: "DELETE" });
            }}
          >
            Delete
          </button>
        )}
      </div>
      <form className="settings-form" onSubmit={rename}>
        <label>
          Name
          <span className="input-row">
            <input value={name} maxLength={calendarNameMax} onChange={(e) => setName(e.target.value)} />
            <button type="submit" className="btn btn-small" disabled={busy || !name.trim() || name.trim() === c.name}>
              Rename
            </button>
          </span>
        </label>
        <ColorPicker value={c.color} disabled={busy} onChange={(color) => void run(path, { method: "PATCH", body: { color } })} />
      </form>

      <h3 className="cal-subhead">People</h3>
      {members.length === 0 && pending.length === 0 && <p className="muted small">Only you. Invite people below.</p>}
      <ul className="person-list">
        {members.map((m) => (
          <li key={m.uid} className="person-row">
            <Avatar name={m.name} url={m.photoUrl ?? undefined} size={32} />
            <span>
              <b>{m.name}</b>
              {m.username && <small className="muted"> @{m.username}</small>}
            </span>
            <select
              aria-label={`What ${m.name} can do`}
              value={m.role}
              disabled={busy}
              onChange={(e) =>
                void run(`${path}/members/${encodeURIComponent(m.uid)}`, { method: "PATCH", body: { role: e.target.value } })
              }
            >
              {shareRoles.map((r) => (
                <option key={r} value={r}>
                  {shareRoleLabels[r]}
                </option>
              ))}
            </select>
            <button
              type="button"
              className="btn btn-small"
              disabled={busy}
              onClick={() => void run(`${path}/members/${encodeURIComponent(m.uid)}`, { method: "DELETE" })}
            >
              Remove
            </button>
          </li>
        ))}
        {pending.map((m) => (
          <li key={m.uid} className="person-row">
            <Avatar name={m.name} url={m.photoUrl ?? undefined} size={32} />
            <span>
              <b>{m.name}</b>
              <small className="muted"> · Invited, {shareRoleLabels[m.role].toLowerCase()}</small>
            </span>
            <button
              type="button"
              className="btn btn-small"
              disabled={busy}
              onClick={() => void run(`${path}/invites/${encodeURIComponent(m.uid)}`, { method: "DELETE" })}
            >
              Cancel invite
            </button>
          </li>
        ))}
      </ul>
      {people < calendarPeopleMax ? (
        <div className="cal-invite">
          <label className="cal-invite-role">
            Invite as
            <select value={role} disabled={busy} onChange={(e) => setRole(e.target.value as ShareRole)}>
              {shareRoles.map((r) => (
                <option key={r} value={r}>
                  {shareRoleLabels[r]}
                </option>
              ))}
            </select>
          </label>
          <PersonPicker
            label="Invite someone by name or username"
            exclude={[c.owner.uid, ...members.map((m) => m.uid), ...pending.map((m) => m.uid)]}
            disabled={busy}
            onPick={(p) => void run(`${path}/invites`, { method: "POST", body: { uid: p.uid, role } })}
          />
          <p className="muted small">
            They get an invite and see nothing until they accept. Can view shows each event&apos;s title, time and place,
            not its notes; Can edit lets them add and change events too.
          </p>
        </div>
      ) : (
        <p className="muted small">A calendar can have up to {calendarPeopleMax} people.</p>
      )}
    </div>
  );
}

function NewCalendar({ busy, run }: { busy: boolean; run: Call }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [color, setColor] = useState<CalendarColor>("blue");

  if (!open) {
    return (
      <p>
        <button type="button" className="btn" onClick={() => setOpen(true)}>
          New calendar
        </button>
      </p>
    );
  }
  return (
    <form
      className="card settings-form"
      onSubmit={(e) => {
        e.preventDefault();
        void run("/v1/me/calendars", { method: "POST", body: { name, color } }).then(() => {
          setOpen(false);
          setName("");
        });
      }}
    >
      <h2 className="card-title">New calendar</h2>
      <label>
        Name
        <input value={name} required maxLength={calendarNameMax} placeholder="e.g. Training" onChange={(e) => setName(e.target.value)} />
      </label>
      <ColorPicker value={color} onChange={setColor} />
      <div className="form-actions">
        <button type="button" className="btn" onClick={() => setOpen(false)}>
          Cancel
        </button>
        <button type="submit" className="btn btn-primary" disabled={busy || !name.trim()}>
          Create
        </button>
      </div>
    </form>
  );
}

/** The private subscription link (every calendar the member is on, as iCalendar). */
function Subscribe() {
  const { user } = useAuth();
  const [feed, setFeed] = useState<CalendarFeedResponse | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!user) return;
    callApi<CalendarFeedResponse>(user, "/v1/me/calendar-feed").then(setFeed, (e) => setError(problem(e)));
  }, [user]);

  if (!user) return null;
  const me = user;

  async function change(method: "POST" | "DELETE") {
    setBusy(true);
    setError(null);
    try {
      setFeed(
        method === "POST"
          ? await callApi<CalendarFeedResponse>(me, "/v1/me/calendar-feed", { method })
          : (await callApi(me, "/v1/me/calendar-feed", { method }), { url: null, webcal: null }),
      );
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card" id="subscribe">
      <h2 className="card-title">Outlook, Apple and Google Calendar</h2>
      <p className="muted small">
        Subscribe with a private link and every calendar you&apos;re on shows up there, kept up to date (calendar apps check
        every hour or so). Anyone with the link can see those events, so keep it to yourself; reset it if it gets out.
        Each event on <Link href="/schedule">your schedule</Link> also has <b>Add to calendar</b>.
      </p>
      {feed?.url && feed.webcal ? (
        <>
          <div className="input-row">
            <input readOnly value={feed.url} aria-label="Subscription link" onFocus={(e) => e.target.select()} />
            <button
              type="button"
              className="btn btn-small"
              onClick={() => {
                void navigator.clipboard?.writeText(feed.url!).then(() => {
                  setCopied(true);
                  setTimeout(() => setCopied(false), 2000);
                });
              }}
            >
              {copied ? "Copied" : "Copy"}
            </button>
          </div>
          <p className="cal-subscribe">
            <a className="btn btn-primary btn-small" href={feed.webcal}>
              Apple Calendar or Outlook
            </a>
            <a
              className="btn btn-small"
              href={`https://calendar.google.com/calendar/r?cid=${encodeURIComponent(feed.webcal)}`}
              target="_blank"
              rel="noopener noreferrer"
            >
              Google Calendar
            </a>
          </p>
          <p className="muted small">
            Outlook on the web: Add calendar → Subscribe from web, and paste the link.{" "}
            <button
              type="button"
              className="text-btn"
              disabled={busy}
              onClick={() => {
                if (window.confirm("Make a new link? The old one stops working, so re-subscribe with the new one.")) {
                  void change("POST");
                }
              }}
            >
              Reset link
            </button>{" "}
            ·{" "}
            <button
              type="button"
              className="text-btn"
              disabled={busy}
              onClick={() => {
                if (window.confirm("Turn the link off? Calendars subscribed to it stop updating.")) void change("DELETE");
              }}
            >
              Turn off
            </button>
          </p>
        </>
      ) : (
        feed && (
          <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={() => void change("POST")}>
            Get a subscription link
          </button>
        )
      )}
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}
