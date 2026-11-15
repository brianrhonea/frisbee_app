import type { Metadata } from "next";
import { PlayerSignups } from "@/components/drafts/PlayerSignups";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = { title: "Players" };

type Props = { params: Promise<{ tournamentId: string }>; searchParams: Promise<{ division?: string }> };

/** A player-entry event's signups and teams on a page of their own (the tournament page has them as its Players tab). */
export default async function TournamentSignupsPage({ params, searchParams }: Props) {
  const { tournamentId } = await params;
  const { division } = await searchParams;
  return (
    <div className="page page-wide">
      <header className="page-head">
        <h1>Players</h1>
      </header>
      <MembersOnly next={`/tournaments/${encodeURIComponent(tournamentId)}/signups${division ? `?division=${encodeURIComponent(division)}` : ""}`} what="Sign up free or log in to sign up for this event.">
        <PlayerSignups tournamentId={tournamentId} divisionId={division} />
      </MembersOnly>
    </div>
  );
}
