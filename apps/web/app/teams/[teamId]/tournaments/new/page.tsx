import type { Metadata } from "next";
import { TournamentEditorPage } from "@/components/team/group_tournaments/TournamentEditor";

export const metadata: Metadata = { title: "New tournament" };

export default async function NewGroupTournamentPage({ searchParams }: { searchParams: Promise<{ event?: string }> }) {
  const { event } = await searchParams;
  return <TournamentEditorPage tournamentId={null} eventId={typeof event === "string" ? event : null} />;
}
