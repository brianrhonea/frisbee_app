import type { Metadata } from "next";
import { SeasonStatsPage } from "@/components/team/stats/SeasonStatsPage";

export const metadata: Metadata = { title: "Season stats" };

export default function TeamSeasonStatsPage() {
  return <SeasonStatsPage />;
}
