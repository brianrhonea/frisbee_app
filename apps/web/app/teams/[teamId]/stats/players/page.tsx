import type { Metadata } from "next";
import { RosterPlayersPage } from "@/components/team/stats/RosterPlayersPage";

export const metadata: Metadata = { title: "Roster players" };

export default function TeamRosterPlayersPage() {
  return <RosterPlayersPage />;
}
