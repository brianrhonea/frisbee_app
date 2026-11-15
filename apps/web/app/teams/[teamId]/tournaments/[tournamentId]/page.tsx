import type { Metadata } from "next";
import { GroupTournamentPage } from "@/components/team/group_tournaments/GroupTournamentPage";

export const metadata: Metadata = { title: "Tournament" };

export default async function GroupTournamentRoute({ params }: { params: Promise<{ tournamentId: string }> }) {
  const { tournamentId } = await params;
  return <GroupTournamentPage tournamentId={tournamentId} />;
}
