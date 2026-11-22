"use client";
import { type ReactNode, useCallback, useRef, useState } from "react";
import {
  parseDateOnly,
  type Repeat,
  type RepeatFrequency,
  repeatDates,
  repeatFrequencies,
  repeatProblem,
  repeatSummary,
  type Series,
  type SeriesScope,
} from "@stall10/shared";
import { Dialog } from "./Dialog";

/** The browser's time zone, sent with a repeat so its times stay put across clock changes. */
export const browserTimeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

/** `YYYY-MM-DD` [days] after the date of a `datetime-local` value. */
function addDays(local: string, days: number): string {
  const d = parseDateOnly(local.slice(0, 10));
  const x = new Date(Date.UTC(d.year, d.month - 1, d.day + days));
  return x.toISOString().slice(0, 10);
}

/**
 * Repeat for a new event (the app's _RepeatFields): does not repeat,
 * daily, weekly on its weekday, every 2 weeks or monthly on its day, until
 * an end date, with how many events that makes or why it can't be saved.
 * [startsAt] is the form's `datetime-local` value.
 */
export function RepeatField({
  startsAt,
  value,
  onChange,
}: {
  startsAt: string;
  value: Repeat | null;
  onChange: (r: Repeat | null) => void;
}) {
  const day = startsAt ? parseDateOnly(startsAt.slice(0, 10)) : null;
  const date = day ? new Date(day.year, day.month - 1, day.day) : null;
  const weekday = date?.toLocaleDateString(undefined, { weekday: "long" }) ?? "";
  const label = (f: RepeatFrequency) =>
    ({
      daily: "Daily",
      weekly: `Weekly on ${weekday}`,
      biweekly: `Every 2 weeks on ${weekday}`,
      monthly: `Monthly on day ${day?.day ?? ""}`,
    })[f];
  const problem = value && day ? repeatProblem(day, value) : null;
  const count = value && day ? repeatDates(day, value).length : 0;
  return (
    <div className="repeat-field">
      <div className="form-row">
        <label>
          Repeat
          <select
            value={value?.freq ?? ""}
            disabled={!startsAt}
            onChange={(e) =>
              onChange(
                e.target.value
                  ? // Seven weeks on by default: eight weekly events.
                    { freq: e.target.value as RepeatFrequency, until: value?.until ?? addDays(startsAt, 49) }
                  : null,
              )
            }
          >
            <option value="">Does not repeat</option>
            {repeatFrequencies.map((f) => (
              <option key={f} value={f}>
                {label(f)}
              </option>
            ))}
          </select>
        </label>
        {value && (
          <label>
            Ends on
            <input
              type="date"
              required
              value={value.until}
              min={startsAt.slice(0, 10)}
              max={addDays(startsAt, 366)}
              onChange={(e) => onChange({ ...value, until: e.target.value })}
            />
          </label>
        )}
      </div>
      {value && (
        <small className={problem ? "form-error" : "muted"} role={problem ? "alert" : undefined}>
          {problem ?? `Creates ${count} events`}
        </small>
      )}
    </div>
  );
}

/** Why [repeat] from the form's start can't be saved, or null. */
export function repeatFormProblem(startsAt: string, repeat: Repeat | null): string | null {
  if (!repeat || !startsAt) return null;
  return repeatProblem(parseDateOnly(startsAt.slice(0, 10)), repeat);
}

/** "Repeats weekly until Mar 3, 2027", with the repeat mark, on a series event. */
export function RepeatNote({ series }: { series: Pick<Series, "freq" | "until"> }) {
  return (
    <small className="muted repeat-note">
      <span aria-hidden="true">↻ </span>
      {repeatSummary(series)}
    </small>
  );
}

/**
 * Asks whether a change to an event in a repeating series is for it alone
 * or for it and every later one (the app's askSeriesScope). [ask] resolves
 * null when cancelled; render [dialog] somewhere in the component.
 */
export function useSeriesScope(): {
  ask: (title: string, action: string) => Promise<SeriesScope | null>;
  dialog: ReactNode;
} {
  const [open, setOpen] = useState<{ title: string; action: string } | null>(null);
  const resolve = useRef<((s: SeriesScope | null) => void) | null>(null);
  const ask = useCallback(
    (title: string, action: string) =>
      new Promise<SeriesScope | null>((r) => {
        resolve.current = r;
        setOpen({ title, action });
      }),
    [],
  );
  const done = (s: SeriesScope | null) => {
    resolve.current?.(s);
    resolve.current = null;
    setOpen(null);
  };
  const dialog = open && (
    <Dialog label={open.title} onClose={() => done(null)} className="card scope-dialog" dismissOnBackdrop>
      <h2 className="card-title">{open.title}</h2>
      <p className="muted">This is a repeating event.</p>
      <div className="scope-actions">
        <button type="button" className="btn btn-primary" autoFocus onClick={() => done("one")}>
          {open.action} this event
        </button>
        <button type="button" className="btn" onClick={() => done("following")}>
          {open.action} this and following events
        </button>
        <button type="button" className="text-btn" onClick={() => done(null)}>
          Cancel
        </button>
      </div>
    </Dialog>
  );
  return { ask, dialog };
}

/** `?scope=following` for "this and following", nothing for one. */
export const scopeQuery = (scope: SeriesScope) => (scope === "following" ? "?scope=following" : "");
