import type { Metadata } from "next";
import { Suspense } from "react";
import { MembersOnly } from "@/components/MembersOnly";
import { Rankings } from "@/components/Rankings";

export const metadata: Metadata = {
  title: "Rankings",
  description: "Team rankings from public tournaments on Stall 10, and player ratings from logged stats.",
};

export default function RankingsPage() {
  return (
    <div className="page page-wide">
      <header className="page-head">
        <h1>Rankings</h1>
        <p>Teams from public tournaments, players from logged stats.</p>
      </header>
      <MembersOnly next="/rankings">
        <Suspense>
          <Rankings />
        </Suspense>
      </MembersOnly>
    </div>
  );
}
