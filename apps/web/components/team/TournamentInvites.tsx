"use client";
import { inviteExpiredMessage, type TeamEntryToFinish, type TeamTournamentInvitesResult } from "@stall10/shared";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { LocalTime } from "../LocalTime";
import { DateTile } from "./DateTile";

const respondPath = (tournamentId: string, teamId: string, step?: string) =>
  `/tournaments/${encodeURIComponent(tournamentId)}/enter?team=${encodeURIComponent(teamId)}${step ? `&step=${step}` : ""}`;

/**
 * A team's tournament business, for its admins
 * (`GET /v1/teams/:id/tournament-invites`; the app's TournamentInvitesCard):
 * invites waiting on it, each with its reply-by time and Respond (the
 * respond flow: accept or decline, then roster and payment), and entries
 * still missing a roster or fee, each with Finish entry. Expired invites
 * say so. Nothing shows when there's nothing to do.
 */
export function TournamentInvites({ teamId }: { teamId: string }) {
  const { user } = useAuth();
  const [data, setData] = useState<TeamTournamentInvitesResult | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    try {
      setData(await callApi<TeamTournamentInvitesResult>(user, `/v1/teams/${encodeURIComponent(teamId)}/tournament-invites`));
    } catch {
      // Not worth a banner on the team page: the event page has them too.
      setData({ invites: [], toFinish: [] });
    }
  }, [user, teamId]);
  useEffect(() => void load(), [load]);

  const invites = data?.invites ?? [];
  const toFinish = data?.toFinish ?? [];
  if (invites.length === 0 && toFinish.length === 0) return null;
  return (
    <section className="card tournament-invites">
      {invites.length > 0 && (
        <>
          <h2 className="card-title">{invites.length === 1 ? "Tournament invite" : `Tournament invites · ${invites.length}`}</h2>
          <ul className="tournament-invite-list">
            {invites.map((i) => (
              <li key={i.tournamentId} className="tournament-invite">
                <DateTile startsAt={i.startsOn} />
                <div className="tournament-invite-main">
                  <Link href={`/tournaments/${encodeURIComponent(i.tournamentId)}`}>
                    <b>{i.name}</b>
                  </Link>
                  <small className="muted">{[i.hostName && `From ${i.hostName}`, i.divisionLabel, i.location].filter(Boolean).join(" · ")}</small>
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
                        <Link className="btn btn-primary btn-small" href={respondPath(i.tournamentId, teamId)}>
                          Respond
                        </Link>
                      </div>
                    </>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </>
      )}
      {toFinish.length > 0 && (
        <>
          <h2 className="card-title">{toFinish.length === 1 ? "Entry to finish" : `Entries to finish · ${toFinish.length}`}</h2>
          <ul className="tournament-invite-list">
            {toFinish.map((e) => (
              <li key={e.tournamentId} className="tournament-invite">
                <DateTile startsAt={e.startsOn} />
                <div className="tournament-invite-main">
                  <Link href={`/tournaments/${encodeURIComponent(e.tournamentId)}`}>
                    <b>{e.name}</b>
                  </Link>
                  <small className="muted">{[e.hostName && `From ${e.hostName}`, e.divisionLabel].filter(Boolean).join(" · ")}</small>
                  <small className={e.overdue ? "entry-overdue" : "muted"}>
                    {stillToDo(e)}
                    {e.deadline && (
                      <>
                        {" "}
                        {e.overdue ? "was due" : "due"} <LocalTime iso={e.deadline} />
                      </>
                    )}
                  </small>
                  <div className="home-actions">
                    <Link className="btn btn-primary btn-small" href={respondPath(e.tournamentId, teamId, e.rosterSet ? "pay" : "roster")}>
                      Finish entry
                    </Link>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
}

/** "Roster and fee", "Roster" or "Fee". */
function stillToDo(e: TeamEntryToFinish): string {
  if (!e.rosterSet && !e.paid) return "Roster and fee";
  return e.rosterSet ? "Fee" : "Roster";
}
