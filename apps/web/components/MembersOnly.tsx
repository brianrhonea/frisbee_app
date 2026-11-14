"use client";
import Link from "next/link";
import type { ReactNode } from "react";
import { useAuth } from "./AuthProvider";

/**
 * Its children for signed-in members; a sign-up / log-in prompt for
 * visitors, who see only team and community pages. Children never render
 * for visitors, so gated pages must fetch their data here, in the browser,
 * with the member's token (not on the server, where it would ship in the
 * page to everyone).
 */
export function MembersOnly({ children, next, what }: { children: ReactNode; next: string; what?: string }) {
  const { user } = useAuth();
  if (user === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
  if (!user) return <JoinPrompt next={next} what={what} />;
  return <>{children}</>;
}

/** Asks a visitor to sign up or log in, then come back to [next]. */
export function JoinPrompt({ next, what }: { next: string; what?: string }) {
  const q = `?next=${encodeURIComponent(next)}`;
  return (
    <div className="card join-prompt">
      <b>Join Stall 10 to see this</b>
      <p className="muted">
        {what ?? "Sign up free or log in to see this page."} Without an account you can browse team and community
        pages.
      </p>
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
