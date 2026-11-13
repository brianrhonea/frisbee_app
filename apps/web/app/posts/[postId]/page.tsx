import type { PublicPost } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { cache } from "react";
import { PostCard } from "@/components/PostCard";
import { getPublic } from "@/lib/api";
import { appScheme } from "@/lib/site";

type Props = { params: Promise<{ postId: string }> };

// One fetch for the metadata and the page.
const load = cache((id: string) => getPublic<PublicPost>(`/v1/public/posts/${encodeURIComponent(id)}`));

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const post = await load((await params).postId);
  const who = post.authorName || "A player";
  const text = post.body?.slice(0, 200) || `A post by ${who} on Stall 10.`;
  return {
    title: { absolute: `${who} on Stall 10` },
    description: text,
    openGraph: { title: `${who} on Stall 10`, description: text, images: post.images?.[0]?.url ?? "/logo.png" },
  };
}

export default async function PostRoute({ params }: Props) {
  const { postId } = await params;
  const post = await load(postId);
  return (
    <div className="page">
      <p>
        <Link href="/community" className="muted">
          ← Community
        </Link>
      </p>
      <PostCard post={post} standalone />
      <div className="cta-card">
        <p>See the replies in the Stall 10 app.</p>
        <a className="btn btn-primary btn-small" href={`${appScheme}://open/p/${encodeURIComponent(post.id)}`}>
          Open in the app
        </a>
      </div>
    </div>
  );
}
