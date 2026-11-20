"use client";
import { clubTooYoungMessage } from "@stall10/shared";
import { orderBy } from "firebase/firestore";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { callApi } from "@/lib/client";
import { useLiveQuery } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { useIsClubTeam } from "./ClubAge";
import "./team_invites.css";

/** users/{uid}/teamInvites/{teamId} (TeamInvite in the app). */
interface TeamInvite {
  teamName?: string;
  kind?: "team" | "community" | "organization";
  invitedBy?: string;
  invitedByName?: string;
  createdAt?: string;
}

/** A club team's invite says it's for players 16 and over; the API checks at Accept. */
function ClubInviteNote({ teamId }: { teamId: string }) {
  return useIsClubTeam(teamId) ? <small>{clubTooYoungMessage}</small> : null;
}

/** What the app calls each kind in a sentence (TeamKind.noun). */
const nouns: Record<string, string> = { team: "team", community: "community", organization: "community" };

/**
 * The member's invitations to teams and groups, newest first, with Accept
 * (joins, then opens the team) and Decline, as the app's Teams tab shows
 * them. Nothing at all when there are none.
 */
export function TeamInvites() {
  const { user } = useAuth();
  const router = useRouter();
  const invites = useLiveQuery<TeamInvite>(user ? `users/${user.uid}/teamInvites` : null, [orderBy("createdAt", "desc")], user?.uid ?? "");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  if (!user || !invites.data || invites.data.length === 0) return null;

  async function answer(teamId: string, accept: boolean) {
    if (!user) return;
    setBusy(teamId);
    setError(null);
    const path = `/v1/me/team-invites/${encodeURIComponent(teamId)}`;
    try {
      await callApi(user, accept ? `${path}/accept` : path, { method: accept ? "POST" : "DELETE" });
      if (accept) router.push(`/teams/${encodeURIComponent(teamId)}`);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="card team-invites" aria-label="Invitations">
      <h2 className="card-title">Invitations</h2>
      <ul className="team-invite-list">
        {invites.data.map((i) => {
          const what = nouns[i.kind ?? "team"] ?? "team";
          return (
            <li key={i.id}>
              <Avatar name={i.teamName || "Team"} size={36} />
              <span className="team-invite-main">
                <b>{i.teamName || "A team"}</b>
                <small>
                  {i.invitedByName ? `${i.invitedByName} invited you to join this ${what}.` : `You were invited to join this ${what}.`}
                </small>
                {(i.kind ?? "team") === "team" && <ClubInviteNote teamId={i.id} />}
              </span>
              <span className="team-invite-actions">
                <button type="button" className="btn btn-small" disabled={busy !== null} onClick={() => void answer(i.id, false)}>
                  Decline
                </button>
                <button type="button" className="btn btn-amber btn-small" disabled={busy !== null} onClick={() => void answer(i.id, true)}>
                  Accept
                </button>
              </span>
            </li>
          );
        })}
      </ul>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}
