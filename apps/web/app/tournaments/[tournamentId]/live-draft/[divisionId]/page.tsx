import type { Metadata } from "next";
import { LiveDraft } from "@/components/drafts/LiveDraft";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = { title: "Captains' draft" };

type Props = { params: Promise<{ tournamentId: string; divisionId: string }> };

/** A division's captains' draft board. */
export default async function TournamentDraftPage({ params }: Props) {
  const { tournamentId, divisionId } = await params;
  return (
    <div className="page page-wide">
      <MembersOnly next={`/tournaments/${tournamentId}/live-draft/${divisionId}`} what="Sign up free or log in to watch the draft.">
        <LiveDraft tournamentId={tournamentId} divisionId={divisionId} />
      </MembersOnly>
    </div>
  );
}
