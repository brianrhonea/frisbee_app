import type { Metadata } from "next";
import { TournamentPage } from "@/components/team/stats/TournamentPage";

export const metadata: Metadata = { title: "Tournament" };

export default async function TeamStatsTournamentPage({ params }: { params: Promise<{ tournamentId: string }> }) {
  const { tournamentId } = await params;
  return <TournamentPage tournamentId={tournamentId} />;
}
