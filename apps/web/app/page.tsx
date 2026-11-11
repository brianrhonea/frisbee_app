import type { EventsPage, PostPage } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { connection } from "next/server";
import { EventItem } from "@/components/EventItem";
import { HomeGate } from "@/components/HomeGate";
import { LocalTime } from "@/components/LocalTime";
import { PostCard } from "@/components/PostCard";
import { getPublic } from "@/lib/api";

export const metadata: Metadata = {
  title: { absolute: "Stall 10 — your ultimate team, in one place" },
  description:
    "Teams, schedules, stats and pickup for ultimate frisbee. Find players, teams and groups near you, and learn to play.",
};

/** How much of the community a visitor sees before signing up. */
const previewPosts = 3;
const previewEvents = 3;

/** Members-only parts, shown to visitors as locked cards. */
const locked = [
  ["Your teams", "Rosters, roles and team chat."],
  ["Your schedule", "Practices, games and RSVPs across every team."],
  ["Your stats", "Goals, assists and blocks, season by season."],
];

export default async function Home() {
  // Rendered per request (the build has no API); the reads stay cached 60s.
  await connection();
  const [feed, upcoming] = await Promise.all([
    getPublic<PostPage>("/v1/public/feed").catch(() => null),
    getPublic<EventsPage>("/v1/public/events").catch(() => null),
  ]);
  const posts = feed?.posts.slice(0, previewPosts) ?? [];
  const events = upcoming?.events.slice(0, previewEvents) ?? [];

  return (
    <HomeGate>
      <div className="page page-wide home">
        <section className="home-hero">
          <p className="eyebrow">Built for ultimate frisbee</p>
          <h1>
            Your ultimate team, <span className="accent">in one place.</span>
          </h1>
          <p className="lead">
            Schedules, rosters, stats and pickup for club, college and league ultimate. Join free to follow players, keep
            up with your teams and see everything happening near you.
          </p>
          <div className="home-actions">
            <Link className="btn btn-primary" href="/sign-up">
              Create your account
            </Link>
            <Link className="btn" href="/sign-in">
              Log in
            </Link>
          </div>
          <p className="web-cta">
            New to ultimate? <Link href="/learn">Learn the basics →</Link>
          </p>
        </section>

        <div className="home-grid">
          <section>
            <h2 className="section-title">From the community</h2>
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
          </section>

          <aside className="stack">
            <h2 className="section-title">Coming up</h2>
            {events.length === 0 ? (
              <p className="empty">Nothing public scheduled.</p>
            ) : (
              events.map((e) => (
                <EventItem key={`${e.teamId}/${e.id}`} startsAt={e.startsAt}>
                  <b>{e.title || "Event"}</b>
                  <small>
                    <LocalTime iso={e.startsAt} style="dateTime" />
                  </small>
                  <small>
                    <Link href={`/teams/${encodeURIComponent(e.teamId)}`}>{e.teamName}</Link>
                  </small>
                </EventItem>
              ))
            )}
            <Link className="link small" href="/events">
              All public events →
            </Link>

            {locked.map(([title, text]) => (
              <div key={title} className="card locked">
                <h3>
                  <span aria-hidden="true">🔒 </span>
                  {title}
                </h3>
                <p className="muted small">{text}</p>
                <Link className="link small" href="/sign-in">
                  Log in to see yours
                </Link>
              </div>
            ))}

            <div className="card learn-card">
              <h3>Never played?</h3>
              <p className="muted small">The rules of ultimate in five minutes: the field, the stall count, and spirit.</p>
              <Link className="btn btn-small" href="/learn">
                Learn to play
              </Link>
            </div>
          </aside>
        </div>
      </div>
    </HomeGate>
  );
}
