"use client";
import type { TeamRoster } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { divisionLabels } from "@/lib/site";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { InvitePeople } from "./InvitePeople";
import { useTeamHub } from "./TeamContext";

/**
 * A community's teams (`teams` in `GET /v1/teams/:id/roster`), for anyone
 * who can see its members. Its member managers invite people to each one.
 */
export function CommunityTeams() {
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const [teams, setTeams] = useState<TeamRoster["teams"] | null>(null);
  const [error, setError] = useState("");
  const [inviting, setInviting] = useState<{ id: string; name: string } | null>(null);
  const canInvite = viewer.state === "member" && viewer.can("manageMembers");

  useEffect(() => {
    if (!user) return;
    setTeams(null);
    setError("");
    callApi<TeamRoster>(user, `/v1/teams/${encodeURIComponent(teamId)}/roster`)
      .then((r) => setTeams(r.teams))
      .catch((e) => setError(e instanceof ApiError ? e.message : "Couldn't load the teams. Try again."));
  }, [user, teamId]);

  if (user === undefined) return null;
  if (!user) {
    return (
      <div className="card hub-empty">
        <p>Log in to see this group&apos;s teams. It&apos;s free.</p>
        <div className="home-actions">
          <Link className="btn btn-primary btn-small" href={`/sign-in?next=${encodeURIComponent(`/teams/${teamId}/teams`)}`}>
            Log in
          </Link>
        </div>
      </div>
    );
  }
  if (error) return <p className="empty">{error}</p>;
  if (!teams) return <p className="muted" aria-busy="true">Loading the teams…</p>;
  if (teams.length === 0) return <p className="empty">No teams here yet. Admins add them in the app.</p>;

  return (
    <div className="stack">
      {inviting && <InvitePeople teamId={inviting.id} teamName={inviting.name} onClose={() => setInviting(null)} />}
      <section className="card">
        <h2 className="card-title">
          {teams.length} {teams.length === 1 ? "team" : "teams"}
        </h2>
        <ul className="team-list">
          {teams.map((t) => (
            <li key={t.id} className="team-row">
              <Link href={`/teams/${encodeURIComponent(t.id)}`}>
                <Avatar name={t.name} size={32} />
                <span>
                  <b>{t.name}</b>
                  {t.division && <small>{divisionLabels[t.division] ?? t.division}</small>}
                </span>
              </Link>
              {canInvite && (
                <button type="button" className="btn btn-small" onClick={() => setInviting({ id: t.id, name: t.name })}>
                  Invite
                </button>
              )}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
