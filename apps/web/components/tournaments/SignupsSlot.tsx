"use client";
// The hosted tournament page's Players tab (events that take players,
// entryType "players"): signups inline, and each division's captains'
// draft board and team editor on their own pages, as they need the room.
// The page is members-only already (MembersOnly around TournamentPage).
import { type DivisionDoc, divisionLabel, type TournamentDoc } from "@stall10/shared";
import Link from "next/link";
import type { Doc } from "@/lib/live";
import { draftHrefs } from "../drafts/data";
import { PlayerSignups } from "../drafts/PlayerSignups";

interface SignupsSlotProps {
  tournamentId: string;
  tournament: Doc<TournamentDoc>;
  /** In the tournament's order. */
  divisions: Array<Doc<DivisionDoc>>;
  /** The division the page has selected. */
  divisionId: string | null;
  /** The viewer manages events for the host. */
  manager: boolean;
}

export function SignupsSlot({ tournamentId, tournament, divisions, divisionId, manager }: SignupsSlotProps) {
  const captains = tournament.draftMode === "captains";
  return (
    <div className="stack" data-slot="tournament-signups">
      <PlayerSignups key={divisionId ?? ""} tournamentId={tournamentId} divisionId={divisionId ?? undefined} />
      {divisions.length > 0 && (manager || captains) && (
        <div className="card">
          <h2 className="card-title">Teams</h2>
          <ul className="hosted-slot-links">
            {divisions.map((d) => (
              <li key={d.id}>
                {captains && <Link href={draftHrefs.liveDraft(tournamentId, d.id)}>{divisionLabel(d)}: captains&apos; draft</Link>}
                {captains && " · "}
                <Link href={draftHrefs.teamDraft(tournamentId, d.id)}>{divisionLabel(d)}: teams</Link>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
