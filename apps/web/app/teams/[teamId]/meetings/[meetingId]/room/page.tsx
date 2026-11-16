import type { Metadata } from "next";
import { MeetingRoom } from "@/components/team/meetings/MeetingRoom";

export const metadata: Metadata = { title: "Meeting room" };

/** The lobby and, once joined, the call. */
export default async function MeetingRoomPage({ params }: { params: Promise<{ meetingId: string }> }) {
  const { meetingId } = await params;
  return <MeetingRoom meetingId={meetingId} />;
}
