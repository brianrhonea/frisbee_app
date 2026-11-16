import type { PostPage } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { connection } from "next/server";
import { HomeGate } from "@/components/HomeGate";
import { LearnPromo, PickupCard } from "@/components/HomeCards";
import { PostCard } from "@/components/PostCard";
import { getPublic, tags } from "@/lib/api";

export const metadata: Metadata = {
  title: { absolute: "Stall 10 — your ultimate team, in one place" },
  description:
    "Teams, schedules, stats and pickup for ultimate frisbee. Find players, teams and groups near you, and learn to play.",
};

/** How much of the community a visitor sees before signing up. */
const previewPosts = 3;

/** Members-only parts, shown to visitors as locked cards. */
const locked = [
  ["Your teams", "Rosters, roles and team chat."],
  ["Your schedule", "Practices, games and RSVPs across every team."],
  ["Players and search", "Profiles, stats and finding people."],
  ["Your stats", "Goals, assists and blocks, season by season."],
];

export default async function Home() {
  // Rendered per request (the build has no API); the reads stay cached 60s.
  await connection();
  // Visitors see the community's newest posts here; events, teams and Learn have their own tabs. No profiles.
  const feed = await getPublic<PostPage>("/v1/public/feed", undefined, { tags: [tags.feed] }).catch(() => null);
  const posts = feed?.posts.slice(0, previewPosts) ?? [];

  return (
    <HomeGate>
      <div className="page huddle home">
        <div className="huddle-main">
          <section className="home-hero">
            <p className="eyebrow">Built for ultimate frisbee</p>
            <h1>
              Your ultimate team, <span className="accent">in one place.</span>
            </h1>
            <p className="lead">
              Schedules, rosters, stats and pickup for club, college and league ultimate. Join free to follow players,
              keep up with your teams and see everything happening near you.
            </p>
            <div className="home-actions">
              <Link className="btn btn-primary" href="/sign-up">
                Create your account
              </Link>
              <Link className="btn btn-quiet" href="/sign-in">
                Log in
              </Link>
            </div>
            <p className="muted small">
              Or look around first: <Link href="/teams#find">find a team</Link>,{" "}
              <Link href="/events">see what&apos;s coming up</Link> or <Link href="/learn">learn to play</Link>.
            </p>
          </section>

          <div className="feed-tabs">
            <Link className="on" href="/community" aria-current="page">
              From the community
            </Link>
          </div>
          {posts.length === 0 ? (
            <p className="empty">No posts yet.</p>
          ) : (
            <div className="stack">
              {posts.map((p) => (
                <PostCard key={p.id} post={p} />
              ))}
            </div>
          )}
          <div className="cta-card">
            <p>Sign up to see the whole feed, follow players and post your own.</p>
            <Link className="btn btn-primary btn-small" href="/sign-up">
              Sign up free
            </Link>
          </div>
        </div>

        <aside className="huddle-side" aria-label="Coming up">
          <PickupCard />

          <div className="card">
            <h2 className="card-title">With a free account</h2>
            <ul className="locked-list">
              {locked.map(([title, text]) => (
                <li key={title}>
                  <b>{title}</b>
                  <small>{text}</small>
                </li>
              ))}
            </ul>
            <Link className="see-all" href="/sign-in">
              Log in to see yours
            </Link>
          </div>

          <LearnPromo label="New to ultimate?" />
        </aside>
      </div>
    </HomeGate>
  );
}
