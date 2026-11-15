import { redirect } from "next/navigation";
import { loadTeam } from "@/lib/teamPage";

type Props = { params: Promise<{ teamId: string }>; searchParams: Promise<{ tab?: string | string[] }> };

const parts = new Set(["playbook", "videos", "stats", "tournaments"]);

/**
 * Old links to More (/more?tab=playbook …): each part has its own page
 * now. Without a tab, a team's goes to its playbook, a group's to its
 * tournaments.
 */
export default async function TeamMoreRedirect({ params, searchParams }: Props) {
  const { teamId } = await params;
  const tab = (await searchParams).tab;
  const asked = typeof tab === "string" && parts.has(tab) ? tab : null;
  const team = (await loadTeam(teamId)).team.kind ?? "team";
  const to = asked ?? (team === "team" ? "playbook" : "tournaments");
  redirect(`/teams/${encodeURIComponent(teamId)}/${to}`);
}
