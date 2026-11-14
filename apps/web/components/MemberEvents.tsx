"use client";
import type { EventsPage } from "@stall10/shared";
import { useEffect, useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "./AuthProvider";
import { EventsBrowser } from "./EventsBrowser";

/** Upcoming public events and tournaments, read with the member's token. */
export function MemberEvents() {
  const { user } = useAuth();
  const [page, setPage] = useState<EventsPage | null | undefined>(undefined);
  useEffect(() => {
    if (!user) return;
    let live = true;
    callApi<EventsPage>(user, "/v1/public/events").then(
      (p) => live && setPage(p),
      () => live && setPage(null),
    );
    return () => {
      live = false;
    };
  }, [user]);
  if (page === undefined) return <p className="muted" aria-busy="true">Loading events…</p>;
  if (page === null) return <p className="form-error">Couldn&apos;t load events. Try again.</p>;
  return <EventsBrowser events={page.events} tournaments={page.tournaments} />;
}
