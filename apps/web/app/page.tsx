import type { EventsPage, PostPage } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { connection } from "next/server";
import { EventItem } from "@/components/EventItem";
import { HomeGate } from "@/components/HomeGate";
import { LocalTime } from "@/components/LocalTime";
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
    getPublic<PostPage>("/v1/public/feed", undefined, { tags: [tags.feed] }).catch(() => null),
    getPublic<EventsPage>("/v1/public/events").catch(() => null),
  ]);
  const posts = feed?.posts.slice(0, previewPosts) ?? [];
  const events = upcoming?.events.slice(0, previewEvents) ?? [];

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
            <div className="card-head">
              <h2 className="card-title">Upcoming events</h2>
              <Link className="see-all" href="/events">
                View all
              </Link>
            </div>
            {events.length === 0 ? (
              <p className="muted small">Nothing public scheduled.</p>
            ) : (
              <div className="date-list">
                {events.map((e) => (
                  <EventItem key={`${e.teamId}/${e.id}`} startsAt={e.startsAt} plain>
                    <b>{e.title || "Event"}</b>
                    <small>
                      <LocalTime iso={e.startsAt} style="dateTime" />
                    </small>
                    <small>
                      <Link href={`/teams/${encodeURIComponent(e.teamId)}`}>{e.teamName}</Link>
                    </small>
                  </EventItem>
                ))}
              </div>
            )}
          </div>

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
