"use client";
import { type ReactNode, useEffect, useRef } from "react";

/**
 * The Month view's list (Schedule): every day of the month that has entries, in order, in a scrollable box.
 * The picked day, or the next day after it that has entries, is highlighted (`picked`) and scrolled into view
 * inside the box; the page itself does not move. A month with nothing says so.
 */
export function ScheduleMonthList<T>({
  days,
  picked,
  label,
  renderRow,
}: {
  days: Array<{ day: Date; items: T[] }>;
  picked: Date;
  /** A day's heading and its section's name, "Thursday, Nov 19". */
  label: (d: Date) => string;
  renderRow: (x: T) => ReactNode;
}) {
  const box = useRef<HTMLDivElement>(null);
  const start = new Date(picked.getFullYear(), picked.getMonth(), picked.getDate()).getTime();
  const target = days.find((x) => x.day.getTime() >= start)?.day.getTime() ?? null;
  useEffect(() => {
    const el = box.current;
    const section = target === null ? null : el?.querySelector<HTMLElement>(`[data-day="${target}"]`);
    if (el && section) el.scrollTop = section.offsetTop - el.offsetTop;
  }, [target, days.length]);
  if (days.length === 0) return <p className="muted small">Nothing scheduled this month</p>;
  return (
    <div className="sched-days sched-month-list" ref={box} tabIndex={0} role="region" aria-label="Events this month">
      {days.map(({ day, items }) => (
        <section key={day.getTime()} data-day={day.getTime()} className={`sched-day${day.getTime() === target ? " picked" : ""}`} aria-label={label(day)}>
          <h3 className="sched-day-head">{label(day)}</h3>
          <ul className="sched-list">{items.map(renderRow)}</ul>
        </section>
      ))}
    </div>
  );
}
