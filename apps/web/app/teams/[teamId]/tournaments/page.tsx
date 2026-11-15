import { redirect } from "next/navigation";

type Props = { params: Promise<{ teamId: string }> };

/** /teams/:id/tournaments has no page of its own: it's More's Tournaments tab. */
export default async function TeamTournamentsIndex({ params }: Props) {
  const { teamId } = await params;
  redirect(`/teams/${encodeURIComponent(teamId)}/more?tab=tournaments`);
}
