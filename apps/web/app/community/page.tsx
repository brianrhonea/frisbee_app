import type { PostPage } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { PostCard } from "@/components/PostCard";
import { getPublic } from "@/lib/api";

export const metadata: Metadata = {
  title: "Community",
  description: "What ultimate players are posting on Stall 10.",
};

type Props = { searchParams: Promise<{ before?: string }> };

export default async function Community({ searchParams }: Props) {
  const before = Number((await searchParams).before) || undefined;
  const page = await getPublic<PostPage>("/v1/public/feed", { before });
  return (
    <div className="page">
      <div className="page-head">
        <h1>Community</h1>
        <p>What players are posting on Stall 10.</p>
      </div>
      {page.posts.length === 0 ? (
        <p className="empty">{before ? "That's everything." : "No posts yet."}</p>
      ) : (
        <div className="stack">
          {page.posts.map((p) => (
            <PostCard key={p.id} post={p} />
          ))}
        </div>
      )}
      {page.next !== null && (
        <nav className="pager">
          <Link className="btn" href={`/community?before=${page.next}`}>
            Older posts
          </Link>
        </nav>
      )}
    </div>
  );
}
