import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { LivePlayer } from "@/components/PlayerPage";

type Props = { params: Promise<{ uid: string }> };

// Members only: profiles are read in the browser with the member's token
// (`/v1/players/:uid`), so nothing about a player ships to visitors.
export const metadata: Metadata = { title: "A player on Stall 10", robots: { index: false } };

export default async function Player({ params }: Props) {
  const { uid } = await params;
  return (
    <MembersOnly next={`/players/${encodeURIComponent(uid)}`} what="Sign up free or log in to see players' profiles.">
      <LivePlayer uid={uid} />
    </MembersOnly>
  );
}
