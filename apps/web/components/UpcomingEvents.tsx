"use client";
import { EventsBrowser } from "./EventsBrowser";
import { usePublicEvents } from "./usePublicEvents";

/** Upcoming public events and tournaments, for members and visitors alike. */
export function UpcomingEvents() {
  const page = usePublicEvents();
  if (page === undefined) return <p className="muted" aria-busy="true">Loading events…</p>;
  if (page === null) return <p className="form-error">Couldn&apos;t load events. Try again.</p>;
  return <EventsBrowser events={page.events} tournaments={page.tournaments} />;
}
