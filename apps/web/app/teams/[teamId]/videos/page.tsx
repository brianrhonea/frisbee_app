import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { TeamPart } from "@/components/team/TeamParts";
import { loadTeam } from "@/lib/teamPage";

type Props = { params: Promise<{ teamId: string }> };

export const metadata: Metadata = { title: "Videos" };

/** A team's videos (members only). */
export default async function TeamVideosPage({ params }: Props) {
  const { teamId } = await params;
  // Groups keep no playbook, videos or stats: their link opens the feed.
  if (((await loadTeam(teamId)).team.kind ?? "team") !== "team") redirect(`/teams/${encodeURIComponent(teamId)}`);
  return <TeamPart part="videos" />;
}
