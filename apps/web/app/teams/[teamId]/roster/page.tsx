import type { Metadata } from "next";
import { TeamRosterView } from "@/components/team/TeamRosterView";

export const metadata: Metadata = { title: "Roster" };

export default function TeamRosterPage() {
  return <TeamRosterView />;
}
