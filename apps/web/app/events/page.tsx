import type { EventsPage } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { connection } from "next/server";
import { EventItem } from "@/components/EventItem";
import { LocalTime } from "@/components/LocalTime";
import { getPublic } from "@/lib/api";

export const metadata: Metadata = {
  title: "Events",
  description: "Upcoming ultimate frisbee games, practices, pickup and tournaments on Stall 10.",
};

export default async function Events() {
  // Render per request, not at build (which has no API). Unlike
  // `dynamic = "force-dynamic"`, this keeps the fetch's 60-second cache.
  await connection();
  const { events, tournaments } = await getPublic<EventsPage>("/v1/public/events");
  return (
    <div className="page">
      <div className="page-head">
        <h1>Events</h1>
        <p>What&apos;s coming up for public teams and groups.</p>
      </div>
      {tournaments.length > 0 && (
        <>
          <h2 className="section-title">Tournaments</h2>
          <div className="stack">
            {tournaments.map((t) => (
              <EventItem key={t.id} startsAt={t.startsAt}>
                <b>{t.name || "Tournament"}</b>
                <small>
                  <LocalTime iso={t.startsAt} />
                  {t.endsOn && t.endsOn !== t.startsAt?.slice(0, 10) ? ` – ${t.endsOn}` : ""}
                </small>
                {t.groupId && (
                  <small>
                    <Link href={`/teams/${encodeURIComponent(t.groupId)}`}>Hosted by a group on Stall 10</Link>
                  </small>
                )}
              </EventItem>
            ))}
          </div>
        </>
      )}
      <h2 className="section-title">Team events</h2>
      {events.length === 0 ? (
        <p className="empty">Nothing coming up.</p>
      ) : (
        <div className="stack">
          {events.map((e) => (
            <EventItem key={`${e.teamId}/${e.id}`} startsAt={e.startsAt}>
              <b>{e.title || "Event"}</b>
              <small>
                <LocalTime iso={e.startsAt} style="dateTime" />
                {e.location ? ` · ${e.location}` : ""}
              </small>
              <small>
                <Link href={`/teams/${encodeURIComponent(e.teamId)}`}>{e.teamName}</Link>
              </small>
            </EventItem>
          ))}
        </div>
      )}
    </div>
  );
}
