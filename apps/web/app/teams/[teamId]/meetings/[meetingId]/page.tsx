import type { Metadata } from "next";
import { MeetingEditorPage } from "@/components/team/meetings/MeetingEditor";
import { MeetingPage } from "@/components/team/meetings/MeetingPage";

export const metadata: Metadata = { title: "Meeting" };

/** One meeting, or "new" to schedule one. */
export default async function TeamMeetingPage({ params }: { params: Promise<{ meetingId: string }> }) {
  const { meetingId } = await params;
  return meetingId === "new" ? <MeetingEditorPage meetingId={null} /> : <MeetingPage meetingId={meetingId} />;
}
