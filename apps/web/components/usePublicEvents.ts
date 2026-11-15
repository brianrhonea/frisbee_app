"use client";
import type { EventsPage } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useEffect, useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "./AuthProvider";

// One `/v1/public/events` read for every part of the page that lists
// upcoming events (Events itself and the right column's Upcoming card),
// reused for a minute.
const fresh = 60_000;
let cached: { uid: string; at: number; page: Promise<EventsPage> } | null = null;

function load(user: User): Promise<EventsPage> {
  if (cached && cached.uid === user.uid && Date.now() - cached.at < fresh) return cached.page;
  const page = callApi<EventsPage>(user, "/v1/public/events");
  const entry = { uid: user.uid, at: Date.now(), page };
  cached = entry;
  // A failure isn't kept: the next view asks again.
  page.catch(() => {
    if (cached === entry) cached = null;
  });
  return page;
}

/** Upcoming public events and tournaments for the signed-in member: undefined while loading, null if it failed. */
export function usePublicEvents(): EventsPage | null | undefined {
  const { user } = useAuth();
  const [page, setPage] = useState<EventsPage | null | undefined>(undefined);
  useEffect(() => {
    if (!user) return;
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
