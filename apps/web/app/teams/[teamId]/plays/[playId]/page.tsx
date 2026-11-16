import type { Metadata } from "next";
import { PlayPage } from "@/components/team/playbook/PlayPage";

export const metadata: Metadata = { title: "Play" };

export default async function TeamPlayPage({ params }: { params: Promise<{ playId: string }> }) {
  const { playId } = await params;
  return <PlayPage playId={playId} />;
}
