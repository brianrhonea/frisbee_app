import type { Metadata } from "next";
import { GamePage } from "@/components/team/stats/GamePage";

export const metadata: Metadata = { title: "Game" };

export default async function TeamStatsGamePage({ params }: { params: Promise<{ gameId: string }> }) {
  const { gameId } = await params;
  return <GamePage gameId={gameId} />;
}
