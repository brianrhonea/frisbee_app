import type { Metadata } from "next";
import { Suspense } from "react";
import { MyTeams } from "@/components/MyTeams";
import { TeamFinder } from "@/components/TeamFinder";
import { TeamInvites } from "@/components/TeamInvites";

export const metadata: Metadata = {
  title: "Teams",
  description: "Your ultimate teams, pickup communities and schools or clubs on Stall 10, and any team's public page.",
};

/**
 * The Teams tab: invitations, then the member's teams and communities (a
 * sign-up card for visitors), then the team finder, which anyone can use
 * to open a team's public page.
 */
export default function Teams() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Teams</h1>
        <p>Your teams, pickup communities and schools or clubs, and any team&apos;s public page.</p>
      </header>
      <div className="stack">
        <TeamInvites />
        <MyTeams />
        <Suspense>
          <TeamFinder />
        </Suspense>
      </div>
    </div>
  );
}
