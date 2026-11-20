import { redirect } from "next/navigation";

type Props = { params: Promise<{ teamId: string }> };

/** /teams/:id/whiteboards has no page of its own: it's the Playbook's Whiteboard view. */
export default async function TeamWhiteboardsIndex({ params }: Props) {
  const { teamId } = await params;
  redirect(`/teams/${encodeURIComponent(teamId)}/playbook?view=whiteboard`);
}
