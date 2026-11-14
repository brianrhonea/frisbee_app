import type { Metadata } from "next";
import { MemberEvents } from "@/components/MemberEvents";
import { MembersOnly } from "@/components/MembersOnly";
import { ScheduleLink } from "@/components/ScheduleLink";

export const metadata: Metadata = {
  title: "Events",
  description: "Upcoming ultimate frisbee games, practices, pickup and tournaments on Stall 10.",
};

/** Members only: read in the browser with their token, so nothing ships to visitors. */
export default function Events() {
  return (
    <div className="page">
      <div className="page-head">
        <h1>Events</h1>
        <p>What&apos;s coming up for public teams and groups.</p>
        <ScheduleLink />
      </div>
      <MembersOnly next="/events" what="Sign up free or log in to find games, practices, pickup and tournaments.">
        <MemberEvents />
      </MembersOnly>
    </div>
  );
}
