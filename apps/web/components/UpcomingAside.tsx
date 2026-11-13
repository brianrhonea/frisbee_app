"use client";
import type { EventsPage } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { getPublicInBrowser } from "@/lib/client";
import { EventItem } from "./EventItem";
import { ForVisitors } from "./ForVisitors";
import { LocalTime } from "./LocalTime";

const shown = 4;

/** The right column: what's coming up, and a sign-up prompt for visitors. */
export function UpcomingAside() {
  const [page, setPage] = useState<EventsPage | null | undefined>(undefined);
  useEffect(() => {
    void getPublicInBrowser<EventsPage>("/v1/public/events").then(setPage);
  }, []);

  const items = [
    ...(page?.tournaments ?? []).map((t) => ({
      id: `t-${t.id}`,
      startsAt: t.startsAt,
      title: t.name || "Tournament",
      href: "/events",
    })),
    ...(page?.events ?? []).map((e) => ({
      id: `e-${e.id}`,
      startsAt: e.startsAt,
      title: e.title || "Event",
      href: `/teams/${encodeURIComponent(e.teamId)}`,
    })),
  ]
    .sort((a, b) => (a.startsAt ?? "").localeCompare(b.startsAt ?? ""))
    .slice(0, shown);

  return (
    <>
      <div className="card">
        <h2 className="card-title">Coming up</h2>
        {page === undefined ? (
          <p className="muted small">Loading…</p>
        ) : items.length === 0 ? (
          <p className="muted small">Nothing coming up yet.</p>
        ) : (
          <div className="aside-events">
            {items.map((i) => (
              <EventItem key={i.id} startsAt={i.startsAt}>
                <Link href={i.href}>
                  <b>{i.title}</b>
                </Link>
                <small>
                  <LocalTime iso={i.startsAt} />
                </small>
              </EventItem>
            ))}
          </div>
        )}
        <p className="small">
          <Link href="/events">All events →</Link>
        </p>
      </div>
      <ForVisitors>
        <div className="card">
          <h2 className="card-title">New to Stall 10?</h2>
          <p className="muted small">Follow players, join teams and groups, and keep up with your season.</p>
          <Link className="btn btn-primary btn-small" href="/sign-up">
            Sign up free
          </Link>
        </div>
      </ForVisitors>
    </>
  );
}
