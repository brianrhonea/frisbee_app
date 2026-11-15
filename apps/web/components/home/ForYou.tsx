"use client";
// The home page's "For you" feed and "Team post" picker (the app's
// HomeScreen: _Tab.forYou and the composer's Team post button).
import { where } from "firebase/firestore";
import Link from "next/link";
import { useState } from "react";
import { PostCard } from "@/components/PostCard";
import { TeamPostCard } from "@/components/team/TeamPostCard";
import { TeamPostComposer } from "@/components/team/TeamPostComposer";
import { canOn } from "@/components/tournaments/useTournament";
import type { TeamDoc } from "@/components/team/TeamContext";
import { useLiveQuery } from "@/lib/live";
import { type UserPages, useForYou } from "./useForYou";
import "./home_feed.css";

/** The member's teams, live (rules: members read their teams). */
export function useMyTeams(uid: string | undefined) {
  return useLiveQuery<TeamDoc>(uid ? "teams" : null, uid ? [where("memberIds", "array-contains", uid)] : [], uid ?? "");
}

export function ForYouFeed({ uid, users, onCommunity }: { uid: string; users: UserPages & { busy: boolean; error: boolean }; onCommunity: () => void }) {
  const teams = useMyTeams(uid);
  const feed = useForYou(uid, teams.data ?? (teams.error ? [] : undefined), users);

  return (
    <div role="tabpanel" aria-label="For you">
      {feed.items.length === 0 ? (
        !feed.loaded || users.busy ? (
          <p className="empty" aria-busy="true">
            Loading posts…
          </p>
        ) : users.error ? (
          <p className="post-error">Couldn&apos;t load posts. Try again.</p>
        ) : (
          <div className="card">
            <p className="muted small">
              {feed.followsAnything ? "No posts yet. News you follow shows up here. " : "No posts yet. Follow players, teams and tournaments to see their news here. "}
              <button type="button" className="link-button" onClick={onCommunity}>
                See the community
              </button>{" "}
              or <Link href="/explore">find people and teams to follow</Link>.
            </p>
          </div>
        )
      ) : (
        <div className="stack">
          {feed.items.map((item) =>
            item.kind === "user" ? (
              <PostCard key={item.id} post={item.post} />
            ) : (
              <div key={item.id} className="feed-team-post">
                <Link className="feed-team-link" href={`/teams/${encodeURIComponent(item.teamId)}`}>
                  {item.teamName}
                </Link>
                <TeamPostCard post={item.post} teamName={item.teamName} showAudience={item.member} />
              </div>
            ),
          )}
        </div>
      )}
      {feed.items.length > 0 && (
        <nav className="pager">
          {!feed.hasMore ? (
            <p className="empty">You&apos;re all caught up.</p>
          ) : (
            <button className="btn" type="button" disabled={feed.loadingMore || users.busy} onClick={() => void feed.loadMore()}>
              {feed.loadingMore || users.busy ? "Loading…" : "Older posts"}
            </button>
          )}
          {users.error && <p className="post-error">Couldn&apos;t load more posts. Try again.</p>}
        </nav>
      )}
    </div>
  );
}

/**
 * "Team post": post on one of the teams the member manages, picked first
 * when there's more than one (the app's _compose).
 */
export function TeamPostPicker({ uid }: { uid: string }) {
  const teams = useMyTeams(uid);
  const postable = (teams.data ?? []).filter((t) => canOn(t, uid, "manageTeam")).sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""));
  const [teamId, setTeamId] = useState<string | null>(null);
  if (postable.length === 0) return null;
  const picked = postable.find((t) => t.id === teamId) ?? (postable.length === 1 ? postable[0] : null);
  return (
    <div className="team-post-picker">
      {postable.length > 1 && (
        <label className="small">
          Post to{" "}
          <select value={picked?.id ?? ""} onChange={(e) => setTeamId(e.target.value || null)}>
            <option value="">Pick a team…</option>
            {postable.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name ?? "Team"}
              </option>
            ))}
          </select>
        </label>
      )}
      {picked && <TeamPostComposer key={picked.id} teamId={picked.id} />}
    </div>
  );
}
