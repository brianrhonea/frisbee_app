"use client";
import { useEffect, useRef, useState } from "react";
import { googleCalendarUrl, outlookCalendarUrl } from "@stall10/shared";
import { downloadIcs, type CalendarFileEvent, shareCalendarEvent } from "@/lib/calendar";

/**
 * "Add to calendar": a menu that adds [event] to a calendar the person
 * picks: Google Calendar or Outlook open their new-event page filled in
 * (they choose the calendar and save there), and "Apple / other (.ics)"
 * downloads the file Apple Calendar and the rest open. Share… sends the
 * event to anyone (the share sheet, or copies its details), as the app's
 * Share. The app opens the phone's own new-event editor instead.
 */
export function AddToCalendar({ event }: { event: CalendarFileEvent }) {
  const ref = useRef<HTMLDetailsElement>(null);
  const [note, setNote] = useState<string | null>(null);

  // Closes on a click elsewhere or Escape, as a menu should.
  useEffect(() => {
    const details = ref.current;
    if (!details) return;
    const close = () => {
      details.open = false;
    };
    const onPointer = (e: PointerEvent) => {
      if (details.open && !details.contains(e.target as Node)) close();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && details.open) {
        close();
        details.querySelector("summary")?.focus();
      }
    };
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, []);

  const close = () => {
    if (ref.current) ref.current.open = false;
  };

  return (
    <details ref={ref} className="cal-menu">
      <summary className="text-btn">Add to calendar</summary>
      <span className="menu-list">
        <a href={googleCalendarUrl(event)} target="_blank" rel="noopener noreferrer" onClick={close}>
          Google Calendar
        </a>
        <a href={outlookCalendarUrl(event)} target="_blank" rel="noopener noreferrer" onClick={close}>
          Outlook
        </a>
        <button
          type="button"
          onClick={() => {
            close();
            downloadIcs(event);
          }}
        >
          Apple / other (.ics)
        </button>
        <button
          type="button"
          onClick={() => {
            close();
            void shareCalendarEvent(event).then(
              (r) => setNote(r === "copied" ? "Copied the event's details." : null),
              () => setNote("Couldn't share it."),
            );
          }}
        >
          Share…
        </button>
      </span>
      {note && (
        <small className="muted" role="status">
          {" "}
          {note}
        </small>
      )}
    </details>
  );
}
