import type { Metadata } from "next";
import { VideoPage } from "@/components/team/videos/VideoPage";

export const metadata: Metadata = { title: "Video" };

export default async function TeamVideoPage({ params }: { params: Promise<{ videoId: string }> }) {
  const { videoId } = await params;
  return <VideoPage videoId={videoId} />;
}
