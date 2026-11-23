"use client";
import { inviteExpiredMessage, type TeamTournamentInvite } from "@stall10/shared";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { LocalTime } from "../LocalTime";
import { DateTile } from "./DateTile";

/**
 * Tournament and league invites waiting on a team, for its admins
 * (`GET /v1/teams/:id/tournament-invites`; the app's TournamentInvitesCard):
 * each with its reply-by time and Accept (the enter page, to pick
 * captains) or Decline (the team withdraws). Expired ones say so. Nothing
 * shows when there are none.
 */
export function TournamentInvites({ teamId }: { teamId: string }) {
  const { user } = useAuth();
  const [invites, setInvites] = useState<TeamTournamentInvite[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    try {
      const res = await callApi<{ invites: TeamTournamentInvite[] }>(user, `/v1/teams/${encodeURIComponent(teamId)}/tournament-invites`);
      setInvites(res.invites);
    } catch {
      // Not worth a banner on the team page: the event page has them too.
      setInvites([]);
    }
  }, [user, teamId]);
  useEffect(() => void load(), [load]);

  async function decline(i: TeamTournamentInvite) {
    if (!user || !window.confirm(`Decline the invite to ${i.name}?`)) return;
    setBusy(i.tournamentId);
    setError(null);
    try {
      await callApi(user, `/v1/tournaments/${encodeURIComponent(i.tournamentId)}/entries/${encodeURIComponent(teamId)}/status`, {
        method: "PUT",
        body: { status: "withdrawn" },
      });
      await load();
    } catch (e) {
      setError(problem(e, "Couldn't decline. Try again."));
    } finally {
      setBusy(null);
    }
  }

  if (!invites || invites.length === 0) return null;
  return (
    <section className="card tournament-invites">
      <h2 className="card-title">{invites.length === 1 ? "Tournament invite" : `Tournament invites · ${invites.length}`}</h2>
      <ul className="tournament-invite-list">
        {invites.map((i) => (
          <li key={i.tournamentId} className="tournament-invite">
            <DateTile startsAt={i.startsOn} />
            <div className="tournament-invite-main">
              <Link href={`/tournaments/${encodeURIComponent(i.tournamentId)}`}>
                <b>{i.name}</b>
              </Link>
              <small className="muted">
                {[i.hostName && `From ${i.hostName}`, i.divisionLabel, i.location].filter(Boolean).join(" · ")}
              </small>
              {i.expired ? (
                <small className="muted">
                  <span className="pill">Expired</span> {inviteExpiredMessage}
                </small>
              ) : (
                <>
                  {i.replyBy && (
                    <small className="muted">
                      Reply by <LocalTime iso={i.replyBy} />
                    </small>
                  )}
                  <div className="home-actions">
                    <Link className="btn btn-primary btn-small" href={`/tournaments/${encodeURIComponent(i.tournamentId)}/enter?team=${encodeURIComponent(teamId)}`}>
                      Accept
                    </Link>
                    <button type="button" className="btn btn-small" disabled={busy !== null} onClick={() => void decline(i)}>
                      Decline
                    </button>
                  </div>
                </>
              )}
            </div>
          </li>
        ))}
      </ul>
      {error && <p className="form-error">{error}</p>}
    </section>
  );
}
