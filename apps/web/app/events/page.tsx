import type { Metadata } from "next";
import { ScheduleLink } from "@/components/ScheduleLink";
import { UpcomingEvents } from "@/components/UpcomingEvents";

export const metadata: Metadata = {
  title: "Events",
  description: "Upcoming ultimate frisbee games, practices, pickup and tournaments on Stall 10.",
};

/** Public: anyone sees public teams' and groups' upcoming events. Each member's own schedule is /schedule. */
export default function Events() {
  return (
    <div className="page">
      <div className="page-head">
        <h1>Events</h1>
        <p>What&apos;s coming up for public teams and communities.</p>
        <ScheduleLink />
      </div>
      <UpcomingEvents />
    </div>
  );
}
