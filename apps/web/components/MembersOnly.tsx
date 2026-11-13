"use client";
import Link from "next/link";
import type { ReactNode } from "react";
import { useAuth } from "./AuthProvider";

/** Its children for signed-in members; a log-in prompt for visitors. */
export function MembersOnly({ children, next }: { children: ReactNode; next: string }) {
  const { user } = useAuth();
  if (user === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
  if (!user) {
    const q = `?next=${encodeURIComponent(next)}`;
    return (
      <div className="card">
        <p>Log in to see this page.</p>
        <div className="home-actions">
          <Link className="btn btn-primary btn-small" href={`/sign-in${q}`}>
            Log in
          </Link>
          <Link className="btn btn-small" href={`/sign-up${q}`}>
            Sign up free
          </Link>
        </div>
      </div>
    );
  }
  return <>{children}</>;
}
