import type { Metadata } from "next";
import { WhiteboardPage } from "@/components/team/playbook/Whiteboard";

export const metadata: Metadata = { title: "Whiteboard" };

/** The playbook's whiteboard: a blank one ("new") or a saved sketch. */
export default async function TeamWhiteboardPage({ params }: { params: Promise<{ playId: string }> }) {
  const { playId } = await params;
  return <WhiteboardPage playId={playId} />;
}
