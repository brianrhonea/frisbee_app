"use client";
import type { PublicEvent, PublicTeamPost } from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import Link from "next/link";
import { EventItem } from "../EventItem";
import { LocalTime } from "../LocalTime";
import { useLiveQuery } from "@/lib/live";
import { useTeamHub } from "./TeamContext";
import { type TeamPostView, TeamPostCard } from "./TeamPostCard";
import { useTeamEvents } from "./TeamSchedule";

const postLimit = 30;

/**
 * The hub's front page: posts in the middle (every post, live, for
 * members; the public ones for everyone else), what's coming up beside
 * them.
 */
export function TeamFeed({ publicPosts, publicEvents }: { publicPosts: PublicTeamPost[]; publicEvents: PublicEvent[] }) {
  const { teamId, name, privateGroup, viewer } = useTeamHub();
  const member = viewer.state === "member";
  const live = useLiveQuery<TeamPostView>(
    member ? `teams/${teamId}/posts` : null,
    [orderBy("createdAt", "desc"), limit(postLimit)],
    "feed",
  );
  const events = useTeamEvents(teamId, viewer);
  const posts: TeamPostView[] = member ? (live.data ?? []) : publicPosts;
  const upcoming = (member ? (events.data ?? []) : publicEvents).slice(0, 4);
  const hidden = !member && privateGroup;

  return (
    <div className="hub-feed">
      <section className="stack">
        {viewer.state === "loading" || (member && !live.data && !live.error) ? (
          <p className="muted" aria-busy="true">Loading posts…</p>
        ) : live.error ? (
          <p className="form-error">{live.error}</p>
        ) : hidden ? (
          <p className="empty">Only members see this group&apos;s posts and events.</p>
        ) : posts.length === 0 ? (
          <p className="empty">{member ? "No posts yet." : "No public posts yet."}</p>
        ) : (
          posts.map((p) => <TeamPostCard key={p.id} post={p} teamName={name} showAudience={member} />)
        )}
        {member && <p className="muted small">Posting to the team comes to the website next; post from the app for now.</p>}
      </section>
      <aside className="stack">
        {!hidden && (
          <div className="card">
            <h2 className="card-title">Coming up</h2>
            {upcoming.length === 0 ? (
              <p className="muted small">Nothing scheduled.</p>
            ) : (
              <div className="stack">
                {upcoming.map((e) => (
                  <Link key={e.id} href={`/teams/${teamId}/schedule?event=${e.id}`} className="hub-event-link">
                    <EventItem startsAt={e.startsAt}>
                      <b>{e.title || "Event"}</b>
                      <small>
                        <LocalTime iso={e.startsAt} style="dateTime" />
                      </small>
                    </EventItem>
                  </Link>
                ))}
              </div>
            )}
            <p className="small" style={{ margin: "12px 0 0" }}>
              <Link href={`/teams/${teamId}/schedule`}>Full schedule</Link>
            </p>
          </div>
        )}
        <div className="card">
          <h2 className="card-title">People</h2>
          <p className="muted small">See who&apos;s on the roster and open their profiles.</p>
          <Link className="btn btn-small" href={`/teams/${teamId}/roster`}>
            Open the roster
          </Link>
        </div>
      </aside>
    </div>
  );
}
