import type { EventsPage } from "@stall10/shared";
import type { Metadata } from "next";
import { connection } from "next/server";
import { EventsBrowser } from "@/components/EventsBrowser";
import { ScheduleLink } from "@/components/ScheduleLink";
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
        <ScheduleLink />
      </div>
      <EventsBrowser events={events} tournaments={tournaments} />
    </div>
  );
}
