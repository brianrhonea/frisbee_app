import { isYouthTeam, type PublicRoster, rosterIsPublic } from "@stall10/shared";
import type { Metadata } from "next";
import { TeamRosterView } from "@/components/team/TeamRosterView";
import { getPublicOrNull } from "@/lib/api";
import { loadTeam } from "@/lib/teamPage";

type Props = { params: Promise<{ teamId: string }> };

// Players' names stay out of search engines, even on a public roster.
export const metadata: Metadata = { title: "Roster", robots: { index: false } };

/**
 * The roster. An adult team's (rosterIsPublic) is rendered on the server
 * for visitors and search engines from `/v1/public/teams/:id/roster`;
 * the API checks again and answers 404 for anything else, which shows the
 * members-only note. Signed-in people read the full roster in the browser.
 */
export default async function TeamRosterPage({ params }: Props) {
  const { teamId } = await params;
  const { team } = await loadTeam(teamId);
  const open = rosterIsPublic(team);
  const publicRoster = open
    ? await getPublicOrNull<PublicRoster>(`/v1/public/teams/${encodeURIComponent(teamId)}/roster`).catch(() => null)
    : null;
  return <TeamRosterView publicRoster={publicRoster} youth={isYouthTeam(team)} />;
}
