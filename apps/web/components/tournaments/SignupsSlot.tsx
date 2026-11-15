"use client";
// The hosted tournament page's Players tab (events that take players,
// entryType "players"): signups inline, and each division's captains'
// draft board and team editor on their own pages, as they need the room.
import { type DivisionDoc, divisionLabel, type TournamentDoc } from "@stall10/shared";
import Link from "next/link";
import type { Doc } from "@/lib/live";
import { PlayerSignups } from "../drafts/PlayerSignups";
import { MembersOnly } from "../MembersOnly";

export interface SignupsSlotProps {
  tournamentId: string;
  tournament: Doc<TournamentDoc>;
  /** In the tournament's order. */
  divisions: Array<Doc<DivisionDoc>>;
  /** The division the page has selected. */
  divisionId: string | null;
  /** The viewer manages events for the host. */
  manager: boolean;
  uid: string | undefined;
}

export function SignupsSlot({ tournamentId, tournament, divisions, divisionId, manager }: SignupsSlotProps) {
  const base = `/tournaments/${encodeURIComponent(tournamentId)}`;
  const captains = tournament.draftMode === "captains";
  return (
    <div className="stack" data-slot="tournament-signups">
      <MembersOnly next={base} what="Sign up free or log in to sign up for this event.">
        <PlayerSignups key={divisionId ?? ""} tournamentId={tournamentId} divisionId={divisionId ?? undefined} />
      </MembersOnly>
      {divisions.length > 0 && (manager || captains) && (
        <div className="card">
        <h2 className="card-title">Teams</h2>
        <ul className="hosted-slot-links">
          {divisions.map((d) => (
            <li key={d.id}>
              {captains && <Link href={`${base}/draft/${encodeURIComponent(d.id)}`}>{divisionLabel(d)}: captains&apos; draft</Link>}
              {captains && " · "}
              <Link href={`${base}/team-draft/${encodeURIComponent(d.id)}`}>{divisionLabel(d)}: teams</Link>
            </li>
          ))}
        </ul>
        </div>
      )}
    </div>
  );
}
