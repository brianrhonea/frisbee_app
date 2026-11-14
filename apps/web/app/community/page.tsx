import type { PostPage } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { connection } from "next/server";
import { ForVisitors } from "@/components/ForVisitors";
import { MoreFeed } from "@/components/MoreFeed";
import { PostCard } from "@/components/PostCard";
import { getPublic, tags } from "@/lib/api";

export const metadata: Metadata = {
  title: "Community",
  description: "What ultimate players are posting on Stall 10.",
};

export default async function Community() {
  // Per request, not at build (no API then); the read stays cached 60s.
  await connection();
  const page = await getPublic<PostPage>("/v1/public/feed", undefined, { tags: [tags.feed] });
  // Members read on from the last post shown.
  const last = page.posts.at(-1)?.createdAt;
  const before = last ? Date.parse(last) : null;
  return (
    <div className="page">
      <div className="page-head">
        <h1>Community</h1>
        <p>What players are posting on Stall 10.</p>
      </div>
      {page.posts.length === 0 ? (
        <p className="empty">No posts yet.</p>
      ) : (
        <div className="stack">
          {page.posts.map((p) => (
            <PostCard key={p.id} post={p} />
          ))}
        </div>
      )}
      <MoreFeed before={Number.isFinite(before) ? before : null} />
      <ForVisitors>
        <div className="cta-card">
          <p>That&apos;s the latest. Sign up to follow players and see your whole feed.</p>
          <Link className="btn btn-primary btn-small" href="/sign-up">
            Sign up free
          </Link>
        </div>
      </ForVisitors>
    </div>
  );
}
