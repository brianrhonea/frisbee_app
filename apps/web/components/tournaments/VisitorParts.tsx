"use client";
// Visitors' pieces of a hosted tournament's page (s.visitor): the sign-up
// prompt that stands in for entering, signing up and following, and the
// News tab from the host's public page.
import Link from "next/link";
import { TeamPostCard } from "@/components/team/TeamPostCard";
import type { TournamentState } from "./useTournament";

/** "Sign up free or log in to enter or sign up", returning to [next]. */
export function JoinToTakePart({ next }: { next: string }) {
  const q = `?next=${encodeURIComponent(next)}`;
  return (
    <div className="card join-prompt">
      <b>Want to play?</b>
      <p className="muted">Sign up free or log in to enter a team, sign up to play or follow along.</p>
      <div className="home-actions">
        <Link className="btn btn-primary btn-small" href={`/sign-up${q}`}>
          Sign up free
        </Link>
        <Link className="btn btn-small" href={`/sign-in${q}`}>
          Log in
        </Link>
      </div>
    </div>
  );
}

/** A visitor's News tab: the host's public posts about the event, from its public page. */
export function PublicNews({ s }: { s: TournamentState }) {
  const posts = s.publicNews ?? [];
  const hostName = s.t?.hostName ?? "The host";
  const hostId = s.t?.hostId ?? "";
  return (
    <div className="stack news-tab">
      {posts.length === 0 && (
        <div className="card">
          <p className="muted small">Updates from {hostName} show up here.</p>
        </div>
      )}
      {posts.map((p) => (
        <TeamPostCard key={p.id} post={p} teamName={hostName} />
      ))}
      {posts.length > 0 && hostId && (
        <small className="muted">
          Also on <Link href={`/teams/${encodeURIComponent(hostId)}`}>{hostName}&apos;s page</Link>.
        </small>
      )}
    </div>
  );
}
