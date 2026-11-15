import type { Metadata } from "next";
import { MeetingEditorPage } from "@/components/team/meetings/MeetingEditor";

export const metadata: Metadata = { title: "Edit meeting" };

export default async function EditMeetingPage({ params }: { params: Promise<{ meetingId: string }> }) {
  const { meetingId } = await params;
  return <MeetingEditorPage meetingId={meetingId} />;
}
