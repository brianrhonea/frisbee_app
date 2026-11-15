import type { Metadata } from "next";
import { MeetingsList } from "@/components/team/meetings/MeetingsList";

export const metadata: Metadata = { title: "Meetings" };

export default function TeamMeetingsPage() {
  return <MeetingsList />;
}
