import type { PublicPost } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { cache } from "react";
import { LivePost } from "@/components/PostPage";
import { getPublicOrNull, tags } from "@/lib/api";
import { appScheme } from "@/lib/site";

type Props = { params: Promise<{ postId: string }> };

// One fetch for the metadata and the page; cached until the post changes
// (the API expires its tag). Null when it isn't public: members may still
// see it (a private author who approved them), so the page asks for them.
const load = cache((id: string) =>
  getPublicOrNull<PublicPost>(`/v1/public/posts/${encodeURIComponent(id)}`, undefined, {
    tags: [tags.post(id), tags.posts],
  }),
);

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const post = await load((await params).postId);
  if (!post) return { title: "A post on Stall 10", robots: { index: false } };
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
      <LivePost postId={postId} initial={post} />
      <div className="cta-card">
        <p>See the replies in the Stall 10 app.</p>
        <a className="btn btn-primary btn-small" href={`${appScheme}://open/p/${encodeURIComponent(postId)}`}>
          Open in the app
        </a>
      </div>
    </div>
  );
}
