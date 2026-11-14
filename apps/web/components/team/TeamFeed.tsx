"use client";
import type { PublicEvent, PublicTeamPost } from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import Link from "next/link";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { EventItem } from "../EventItem";
import { LocalTime } from "../LocalTime";
import { useLiveQuery } from "@/lib/live";
import { useTeamHub } from "./TeamContext";
import { type TeamPostView, TeamPostCard } from "./TeamPostCard";
import { TeamPostComposer } from "./TeamPostComposer";
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
  const admin = viewer.state === "member" && viewer.can("manageTeam");
  const [editing, setEditing] = useState<string | null>(null);

  return (
    <div className="hub-feed">
      <section className="stack">
        {admin && <TeamPostComposer teamId={teamId} />}
        {viewer.state === "loading" || (member && !live.data && !live.error) ? (
          <p className="muted" aria-busy="true">Loading posts…</p>
        ) : live.error ? (
          <p className="form-error">{live.error}</p>
        ) : hidden ? (
          <p className="empty">Only members see this group&apos;s posts and events.</p>
        ) : posts.length === 0 ? (
          <p className="empty">{member ? "No posts yet." : "No public posts yet."}</p>
        ) : (
          posts.map((p) =>
            editing === p.id ? (
              <TeamPostComposer key={p.id} teamId={teamId} post={p} onDone={() => setEditing(null)} />
            ) : (
              <TeamPostCard
                key={p.id}
                post={p}
                teamName={name}
                showAudience={member}
                actions={admin ? <PostAdminActions teamId={teamId} postId={p.id} onEdit={() => setEditing(p.id)} /> : undefined}
              />
            ),
          )
        )}
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

/** Edit and delete on a team post, for its admins. */
function PostAdminActions({ teamId, postId, onEdit }: { teamId: string; postId: string; onEdit: () => void }) {
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function remove() {
    if (!user || !window.confirm("Delete this post? This can't be undone.")) return;
    setBusy(true);
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/posts/${encodeURIComponent(postId)}`, { method: "DELETE" });
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }
  return (
    <span className="post-admin">
      <button type="button" className="text-btn" onClick={onEdit} disabled={busy}>
        Edit
      </button>
      <button type="button" className="text-btn danger" onClick={() => void remove()} disabled={busy}>
        Delete
      </button>
      {error && <span className="form-error">{error}</span>}
    </span>
  );
}
