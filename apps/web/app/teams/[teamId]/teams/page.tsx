import type { Metadata } from "next";
import { CommunityTeams } from "@/components/team/CommunityTeams";

export const metadata: Metadata = { title: "Teams" };

export default function CommunityTeamsPage() {
  return <CommunityTeams />;
}
