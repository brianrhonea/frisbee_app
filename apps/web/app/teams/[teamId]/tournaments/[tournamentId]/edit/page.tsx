import type { Metadata } from "next";
import { TournamentEditorPage } from "@/components/team/group_tournaments/TournamentEditor";

export const metadata: Metadata = { title: "Tournament setup" };

export default async function EditGroupTournamentPage({ params }: { params: Promise<{ tournamentId: string }> }) {
  const { tournamentId } = await params;
  return <TournamentEditorPage tournamentId={tournamentId} />;
}
