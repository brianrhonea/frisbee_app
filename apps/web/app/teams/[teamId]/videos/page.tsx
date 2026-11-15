import { redirect } from "next/navigation";

type Props = { params: Promise<{ teamId: string }> };

/** /teams/:id/videos has no page of its own: it's More's Videos tab. */
export default async function TeamVideosIndex({ params }: Props) {
  const { teamId } = await params;
  redirect(`/teams/${encodeURIComponent(teamId)}/more?tab=videos`);
}
