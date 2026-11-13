import type { Metadata } from "next";
import { MyTeams } from "@/components/MyTeams";

export const metadata: Metadata = {
  title: "Teams",
  description: "Your ultimate teams, pickup groups and schools or clubs on Stall 10.",
};

/** The Teams tab: the member's teams and communities. */
export default function Teams() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Teams</h1>
        <p>Your teams, pickup groups and schools or clubs.</p>
      </header>
      <MyTeams />
    </div>
  );
}
