import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { TournamentPage } from "@/components/tournaments/TournamentPage";

export const metadata: Metadata = { title: "Tournament" };

type Props = { params: Promise<{ tournamentId: string }> };

/** A hosted tournament or league: overview, teams, schedule and results. */
export default async function HostedTournamentPage({ params }: Props) {
  const { tournamentId } = await params;
  return (
    <div className="page">
      <MembersOnly next={`/tournaments/${encodeURIComponent(tournamentId)}`} what="Sign up free or log in to see this event.">
        <TournamentPage tournamentId={tournamentId} />
      </MembersOnly>
    </div>
  );
}
