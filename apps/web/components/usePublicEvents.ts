"use client";
import type { EventsPage } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useEffect, useState } from "react";
import { getPublicApi } from "@/lib/client";
import { useAuth } from "./AuthProvider";

// One `/v1/public/events` read for every part of the page that lists
// upcoming events (Events itself and the right column's Upcoming card),
// reused for a minute. Public: visitors read it without a token, members
// with theirs (so they're limited by uid, not IP).
const fresh = 60_000;
let cached: { who: string; at: number; page: Promise<EventsPage> } | null = null;

function load(user: User | null): Promise<EventsPage> {
  const who = user?.uid ?? "";
  if (cached && cached.who === who && Date.now() - cached.at < fresh) return cached.page;
  const page = getPublicApi<EventsPage>(user, "/v1/public/events");
  const entry = { who, at: Date.now(), page };
  cached = entry;
  // A failure isn't kept: the next view asks again.
  page.catch(() => {
    if (cached === entry) cached = null;
  });
  return page;
}

/** Upcoming public events and tournaments, for members and visitors alike: undefined while loading, null if it failed. */
export function usePublicEvents(): EventsPage | null | undefined {
  const { user } = useAuth();
  const [page, setPage] = useState<EventsPage | null | undefined>(undefined);
  useEffect(() => {
    // Still finding out whether someone's signed in.
    if (user === undefined) return;
    let live = true;
    load(user).then(
      (p) => live && setPage(p),
      () => live && setPage(null),
    );
    return () => {
      live = false;
    };
  }, [user]);
  return page;
}
