"use client";
import type { EventsPage } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { EventItem } from "./EventItem";
import { LocalTime } from "./LocalTime";
import { NavIcon } from "./NavIcons";

type Tournament = EventsPage["tournaments"][number];
type TeamEvent = EventsPage["events"][number];

/** Local calendar day, as "2026-11-14". */
function dayKey(d: Date) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const startOfToday = () => {
  const n = new Date();
  return new Date(n.getFullYear(), n.getMonth(), n.getDate());
};

/** The days an event covers: its start day, through a tournament's last day. */
function daysOf(startsAt?: string, endsOn?: string): string[] {
  if (!startsAt) return [];
  const start = new Date(startsAt);
  if (Number.isNaN(start.getTime())) return [];
  const first = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  const days = [dayKey(first)];
  if (endsOn && /^\d{4}-\d{2}-\d{2}$/.test(endsOn)) {
    for (let d = addDays(first, 1), i = 0; dayKey(d) <= endsOn && i < 31; d = addDays(d, 1), i++) days.push(dayKey(d));
  }
  return days;
}

const fmt = (d: Date, o: Intl.DateTimeFormatOptions) => d.toLocaleDateString("en-US", o);

/**
 * Public events with a week strip over them, like the app's Schedule: seven
 * days rolling from today, each with dots for what's on (team events in
 * indigo, tournaments in amber). Picking a day narrows the lists to it.
 */
export function EventsBrowser({ events, tournaments }: EventsPage) {
  // Days are the visitor's local ones, known only in the browser.
  const [today, setToday] = useState<Date | null>(null);
  const [week, setWeek] = useState(0);
  const [picked, setPicked] = useState<string | null>(null);
  useEffect(() => setToday(startOfToday()), []);

  const byDay = useMemo(() => {
    const map = new Map<string, Array<"event" | "tournament">>();
    const add = (k: string, kind: "event" | "tournament") => map.set(k, [...(map.get(k) ?? []), kind]);
    for (const t of tournaments) for (const k of daysOf(t.startsAt, t.endsOn)) add(k, "tournament");
    for (const e of events) for (const k of daysOf(e.startsAt)) add(k, "event");
    return map;
  }, [events, tournaments]);

  const days = today ? Array.from({ length: 7 }, (_, i) => addDays(today, week * 7 + i)) : [];
  const weekCount = days.reduce((n, d) => n + (byDay.get(dayKey(d))?.length ?? 0), 0);
  const on = (startsAt?: string, endsOn?: string) => !picked || daysOf(startsAt, endsOn).includes(picked);
  const shownTournaments = tournaments.filter((t) => on(t.startsAt, t.endsOn));
  const shownEvents = events.filter((e) => on(e.startsAt));
  const pickedDate = picked ? new Date(`${picked}T12:00:00`) : null;

  function moveWeek(by: number) {
    setWeek((w) => Math.max(0, w + by));
    setPicked(null);
  }

  return (
    <>
      <section className="card week-strip" aria-label="Calendar">
        {today ? (
          <>
            <div className="week-head">
              <button type="button" className="icon-btn" aria-label="Previous week" disabled={week === 0} onClick={() => moveWeek(-1)}>
                <NavIcon name="arrow" size={18} />
              </button>
              <div className="week-title">
                <b>
                  {fmt(days[0]!, { month: "short", day: "numeric" })} – {fmt(days[6]!, { month: "short", day: "numeric" })}
                </b>
                <small>{weekCount === 1 ? "1 event" : `${weekCount} events`}</small>
              </div>
              <button type="button" className="icon-btn" aria-label="Next week" onClick={() => moveWeek(1)}>
                <NavIcon name="arrow" size={18} />
              </button>
            </div>
            <div className="week-days">
              {days.map((d) => {
                const k = dayKey(d);
                const kinds = byDay.get(k) ?? [];
                const isToday = week === 0 && k === dayKey(today);
                const selected = picked === k;
                return (
                  <button
                    key={k}
                    type="button"
                    className={["week-day", isToday ? "today" : "", selected ? "selected" : ""].filter(Boolean).join(" ")}
                    aria-pressed={selected}
                    aria-label={`${fmt(d, { weekday: "long", month: "long", day: "numeric" })}: ${
                      kinds.length === 1 ? "1 event" : `${kinds.length} events`
                    }`}
                    onClick={() => setPicked(selected ? null : k)}
                  >
                    <small>{fmt(d, { weekday: "short" })}</small>
                    <b>{d.getDate()}</b>
                    <span className="week-dots" aria-hidden="true">
                      {kinds.slice(0, 3).map((kind, i) => (
                        <i key={i} className={kind} />
                      ))}
                    </span>
                  </button>
                );
              })}
            </div>
            <div className="week-foot">
              <span className="week-legend">
                <i className="event" /> Team events <i className="tournament" /> Tournaments
              </span>
              {week > 0 && (
                <button type="button" className="text-btn" onClick={() => moveWeek(-week)}>
                  This week
                </button>
              )}
            </div>
          </>
        ) : (
          <div className="week-placeholder" aria-busy="true" />
        )}
      </section>

      {pickedDate && (
        <div className="day-filter">
          <h2 className="section-title">{fmt(pickedDate, { weekday: "long", month: "long", day: "numeric" })}</h2>
          <button type="button" className="text-btn" onClick={() => setPicked(null)}>
            Show all upcoming
          </button>
        </div>
      )}

      {shownTournaments.length > 0 && (
        <>
          <h2 className="section-title">Tournaments</h2>
          <div className="stack">
            {shownTournaments.map((t) => (
              <EventItem key={t.id} startsAt={t.startsAt}>
                <b>{t.name || "Tournament"}</b>
                <small>
                  <LocalTime iso={t.startsAt} />
                  {t.endsOn && t.endsOn !== t.startsAt?.slice(0, 10) ? ` – ${t.endsOn}` : ""}
                </small>
                {t.groupId && (
                  <small>
                    <Link href={`/teams/${encodeURIComponent(t.groupId)}`}>Hosted by a group on Stall 10</Link>
                  </small>
                )}
              </EventItem>
            ))}
          </div>
        </>
      )}
      <h2 className="section-title">Team events</h2>
      {shownEvents.length === 0 ? (
        <p className="empty">{picked ? "Nothing on this day." : "Nothing coming up."}</p>
      ) : (
        <div className="stack">
          {shownEvents.map((e) => (
            <EventItem key={`${e.teamId}/${e.id}`} startsAt={e.startsAt}>
              <b>{e.title || "Event"}</b>
              <small>
                <LocalTime iso={e.startsAt} style="dateTime" />
                {e.location ? ` · ${e.location}` : ""}
              </small>
              <small>
                <Link href={`/teams/${encodeURIComponent(e.teamId)}`}>{e.teamName}</Link>
              </small>
            </EventItem>
          ))}
        </div>
      )}
    </>
  );
}
