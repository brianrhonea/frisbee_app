import type { Metadata } from "next";
import { TeamDraft } from "@/components/drafts/TeamDraft";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = { title: "Draft teams" };

type Props = { params: Promise<{ tournamentId: string; divisionId: string }> };

/** The host deals and adjusts a division's teams. */
export default async function TournamentTeamDraftPage({ params }: Props) {
  const { tournamentId, divisionId } = await params;
  return (
    <div className="page page-wide">
      <MembersOnly next={`/tournaments/${tournamentId}/team-draft/${divisionId}`} what="Sign up free or log in to draft teams.">
        <TeamDraft tournamentId={tournamentId} divisionId={divisionId} />
      </MembersOnly>
    </div>
  );
}
