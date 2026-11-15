import { redirect } from "next/navigation";

type Props = { params: Promise<{ teamId: string }> };

/** /teams/:id/plays has no page of its own: it's More's Playbook tab. */
export default async function TeamPlaysIndex({ params }: Props) {
  const { teamId } = await params;
  redirect(`/teams/${encodeURIComponent(teamId)}/more?tab=playbook`);
}
