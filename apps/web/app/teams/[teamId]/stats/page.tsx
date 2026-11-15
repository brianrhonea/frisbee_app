import { redirect } from "next/navigation";

type Props = { params: Promise<{ teamId: string }> };

/** /teams/:id/stats has no page of its own: it's More's Stats tab. */
export default async function TeamStatsIndex({ params }: Props) {
  const { teamId } = await params;
  redirect(`/teams/${encodeURIComponent(teamId)}/more?tab=stats`);
}
