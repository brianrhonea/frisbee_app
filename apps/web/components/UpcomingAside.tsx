"use client";
import Link from "next/link";
import { useAuth } from "./AuthProvider";
import { EventItem } from "./EventItem";
import { ForVisitors } from "./ForVisitors";
import { PickupCard } from "./HomeCards";
import { LocalTime } from "./LocalTime";
import { NavIcon } from "./NavIcons";
import { usePublicEvents } from "./usePublicEvents";

const shown = 4;

/** The right column: what's coming up (for everyone), and a sign-up prompt for visitors. */
export function UpcomingAside() {
  const { user } = useAuth();
  const page = usePublicEvents();

  const items = [
    ...(page?.tournaments ?? []).map((t) => ({
      id: `t-${t.id}`,
      startsAt: t.startsAt,
      title: t.name || "Tournament",
      // A group's tournament has its own page for members; visitors get the group's page (its
      // tournaments are members-only); anything else is on Events.
      href:
        t.groupId && t.tournamentId
          ? user
            ? `/teams/${encodeURIComponent(t.groupId)}/tournaments/${encodeURIComponent(t.tournamentId)}`
            : `/teams/${encodeURIComponent(t.groupId)}`
          : "/events",
    })),
    ...(page?.events ?? []).map((e) => ({
      id: `e-${e.id}`,
      startsAt: e.startsAt,
      title: e.title || "Event",
      href: `/teams/${encodeURIComponent(e.teamId)}/schedule?event=${encodeURIComponent(e.id)}`,
    })),
  ]
    .sort((a, b) => (a.startsAt ?? "").localeCompare(b.startsAt ?? ""))
    .slice(0, shown);

  return (
    <>
      {user !== undefined && (
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
      )}
      <PickupCard />
      <ForVisitors>
        <div className="card promo-card">
          <small>New to Stall 10?</small>
          <b>Good people. Great ultimate.</b>
          <p>Follow players, join teams and communities, and keep up with your season.</p>
          <Link className="btn btn-amber btn-small" href="/sign-up">
            Sign up free <NavIcon name="external" size={14} />
          </Link>
        </div>
      </ForVisitors>
    </>
  );
}
