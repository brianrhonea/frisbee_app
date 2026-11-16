import type { Metadata } from "next";
import { TeamPart } from "@/components/team/TeamParts";

export const metadata: Metadata = { title: "Tournaments" };

/** A team or group's tournaments: the ones it hosts, and its own (group tournaments). */
export default function TeamTournamentsPage() {
  return <TeamPart part="tournaments" />;
}
