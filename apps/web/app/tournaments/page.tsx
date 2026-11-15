import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { FindTournaments } from "@/components/tournaments/TournamentLists";

export const metadata: Metadata = { title: "Tournaments and leagues" };

/** Upcoming hosted tournaments and leagues to find and enter. */
export default function TournamentsPage() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Tournaments and leagues</h1>
        <p>Events hosted on Stall 10: enter a team, sign up to play or follow along.</p>
      </header>
      <MembersOnly next="/tournaments" what="Sign up free or log in to find tournaments and leagues.">
        <FindTournaments />
      </MembersOnly>
    </div>
  );
}
