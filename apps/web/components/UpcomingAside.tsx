"use client";
import type { EventsPage } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { getPublicInBrowser } from "@/lib/client";
import { EventItem } from "./EventItem";
import { ForVisitors } from "./ForVisitors";
import { PickupCard } from "./HomeCards";
import { LocalTime } from "./LocalTime";
import { NavIcon } from "./NavIcons";

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
        <div className="card-head">
          <h2 className="card-title">Upcoming events</h2>
          <Link className="see-all" href="/events">
            View all
          </Link>
        </div>
        {page === undefined ? (
          <p className="muted small">Loading…</p>
        ) : items.length === 0 ? (
          <p className="muted small">Nothing coming up yet.</p>
        ) : (
          <div className="date-list">
            {items.map((i) => (
              <EventItem key={i.id} startsAt={i.startsAt} plain>
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
      </div>
      <PickupCard />
      <ForVisitors>
        <div className="card promo-card">
          <small>New to Stall 10?</small>
          <b>Good people. Great ultimate.</b>
          <p>Follow players, join teams and groups, and keep up with your season.</p>
          <Link className="btn btn-amber btn-small" href="/sign-up">
            Sign up free <NavIcon name="external" size={14} />
          </Link>
        </div>
      </ForVisitors>
    </>
  );
}
