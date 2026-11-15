import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { TournamentForm } from "@/components/tournaments/TournamentForm";

export const metadata: Metadata = { title: "Edit event" };

type Props = { params: Promise<{ tournamentId: string }> };

/** The host edits a tournament's details, format and divisions. */
export default async function EditTournamentPage({ params }: Props) {
  const { tournamentId } = await params;
  return (
    <div className="page">
      <header className="page-head">
        <h1>Edit event</h1>
      </header>
      <MembersOnly next={`/tournaments/${encodeURIComponent(tournamentId)}/edit`}>
        <TournamentForm tournamentId={tournamentId} />
      </MembersOnly>
    </div>
  );
}
