import type { ProfilePage } from "@stall10/shared";
import type { Metadata } from "next";
import { cache } from "react";
import { LivePlayer } from "@/components/PlayerPage";
import { getPublic, tags } from "@/lib/api";

type Props = { params: Promise<{ uid: string }> };

// The public page, cached until the player changes it (the API expires
// the tag). Members then switch to their own live view (LivePlayer).
const load = cache((uid: string) =>
  getPublic<ProfilePage>(`/v1/public/players/${encodeURIComponent(uid)}`, undefined, { tags: [tags.player(uid)] }),
);

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { profile } = await load((await params).uid);
  const name = profile.name || "A player";
  return {
    title: profile.username ? `${name} (@${profile.username})` : name,
    description: profile.private ? `${name} on Stall 10.` : profile.bio?.slice(0, 200) || `${name}'s profile on Stall 10.`,
    openGraph: { images: profile.photoUrl ?? "/logo.png" },
  };
}

/** Anyone's profile as a dashboard: who they are on the left, what they've done on the right. */
export default async function Player({ params }: Props) {
  const { uid } = await params;
  return <LivePlayer uid={uid} initial={await load(uid)} />;
}
