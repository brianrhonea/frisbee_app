import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { Schedule } from "@/components/Schedule";

export const metadata: Metadata = { title: "Your schedule" };

export default function SchedulePage() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Your schedule</h1>
        <p>Your calendars, ones friends share with you, and your teams&apos; events and meetings.</p>
      </header>
      <MembersOnly next="/schedule">
        <Schedule />
      </MembersOnly>
    </div>
  );
}
