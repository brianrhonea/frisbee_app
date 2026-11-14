"use client";
import { type CalendarPerson, type CalendarViewersResponse, calendarViewersMax } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { PersonPicker } from "../PersonPicker";

/**
 * Settings → Calendar sharing: the people who see the player's personal
 * events (title, time and place; never notes) in their own schedule.
 * Each change saves at once.
 */
export function CalendarSharing() {
  const { user } = useAuth();
  const [viewers, setViewers] = useState<CalendarPerson[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    callApi<CalendarViewersResponse>(user, "/v1/me/calendar/viewers").then(
      (r) => setViewers(r.viewers),
      (e) => setError(e instanceof ApiError ? e.message : "Couldn't load who you share with."),
    );
  }, [user]);

  if (!user) return null;
  const me = user;

  async function save(next: CalendarPerson[]) {
    setBusy(true);
    setError(null);
    try {
      const r = await callApi<CalendarViewersResponse>(me, "/v1/me/calendar/viewers", {
        method: "PUT",
        body: { viewers: next.map((v) => v.uid) },
      });
      setViewers(r.viewers);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Couldn't save. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="stack">
      <div className="card">
        <h2 className="card-title">Share your calendar</h2>
        <p className="muted small">
          The people you add see your personal events in their schedule: the title, type, time and place, never your
          notes. Team events aren&apos;t included. Take someone off and they stop seeing it straight away.{" "}
          <Link href="/schedule">Your schedule</Link>
        </p>
        {viewers === null ? (
          !error && <p className="muted">Loading…</p>
        ) : (
          <>
            {viewers.length === 0 ? (
              <p className="muted">You aren&apos;t sharing your calendar with anyone.</p>
            ) : (
              <ul className="person-list">
                {viewers.map((v) => (
                  <li key={v.uid} className="person-row">
                    <Avatar name={v.name} url={v.photoUrl ?? undefined} size={32} />
                    <span>
                      <b>{v.name}</b>
                      {v.username && <small className="muted"> @{v.username}</small>}
                    </span>
                    <button
                      type="button"
                      className="btn btn-small"
                      disabled={busy}
                      onClick={() => void save(viewers.filter((x) => x.uid !== v.uid))}
                    >
                      Stop sharing
                    </button>
                  </li>
                ))}
              </ul>
            )}
            {viewers.length < calendarViewersMax ? (
              <PersonPicker
                label="Add someone by name or username"
                exclude={viewers.map((v) => v.uid)}
                disabled={busy}
                onPick={(p) => void save([...viewers, p])}
              />
            ) : (
              <p className="muted small">You can share with up to {calendarViewersMax} people.</p>
            )}
          </>
        )}
        {error && <p className="form-error">{error}</p>}
      </div>
    </div>
  );
}
