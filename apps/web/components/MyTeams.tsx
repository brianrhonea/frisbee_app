"use client";
import type { MeHome } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { listingSubtitle } from "@/lib/site";
import { useAuth } from "./AuthProvider";
import { roleLabel, TeamList } from "./ProfileDashboard";

/** The signed-in member's teams; a sign-up prompt for visitors. */
export function MyTeams() {
  const { user } = useAuth();
  const [teams, setTeams] = useState<MeHome["teams"] | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!user) return;
    callApi<MeHome>(user, "/v1/me/home")
      .then((h) => setTeams(h.teams))
      .catch((e) => setError(e instanceof ApiError ? e.message : "Couldn't load your teams. Try again."));
  }, [user]);

  if (user === undefined) return null;
  if (!user) {
    return (
      <div className="card">
        <p>Join teams and pickup groups to see their schedules, chat and posts in one place.</p>
        <div className="home-actions">
          <Link className="btn btn-primary btn-small" href="/sign-up?next=/teams">
            Sign up free
          </Link>
          <Link className="btn btn-small" href="/explore">
            Find a team
          </Link>
        </div>
      </div>
    );
  }
  if (error) return <p className="form-error">{error}</p>;
  if (!teams) return <p className="muted" aria-busy="true">Loading your teams…</p>;
  return (
    <TeamList
      title="Your teams and groups"
      teams={teams.map((t) => ({
        id: t.id,
        name: t.name,
        subtitle: [roleLabel(t.role, t.kind), listingSubtitle(t)].filter(Boolean).join(" · "),
      }))}
      empty={
        <p className="muted small">
          No teams yet. <Link href="/explore">Find a team or group</Link>, or start one in the app.
        </p>
      }
    />
  );
}
