import type { Metadata } from "next";
import { TournamentsForEveryone } from "@/components/tournaments/PublicTournament";
import { loadTournaments } from "@/lib/tournamentPage";

export const metadata: Metadata = {
  title: "Tournaments and leagues",
  description: "Tournaments, hat tournaments and leagues hosted on Stall 10: schedules, scores and standings.",
};

/**
 * Upcoming hosted tournaments and leagues to find and enter. Server-rendered
 * for visitors and search engines from the public list; members get it live.
 */
export default async function TournamentsPage() {
  const list = await loadTournaments();
  return (
    <div className="page">
      <header className="page-head">
        <h1>Tournaments and leagues</h1>
        <p>Events hosted on Stall 10: enter a team, sign up to play or follow along.</p>
      </header>
      <TournamentsForEveryone list={list?.tournaments ?? null} />
    </div>
  );
}
