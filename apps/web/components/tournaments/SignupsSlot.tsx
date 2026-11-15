"use client";
// SLOT for the player signups, hat tournament and captains' draft slice,
// which another change builds. The hosted tournament page renders this as
// its Players tab whenever the event takes players (entryType "players"),
// and nothing else of the page depends on it. Until that slice is merged
// it links to its routes; then mount its components here:
//   <PlayerSignups tournamentId={tournamentId} divisionId={divisionId} />
//   <LiveDraft tournamentId={tournamentId} divisionId={id} />   (captains' draft)
//   <TeamDraft tournamentId={tournamentId} divisionId={id} />   (drafting teams)
// from @/components/drafts/..., keeping these props (or widening them).
import { type DivisionDoc, divisionLabel, type TournamentDoc } from "@stall10/shared";
import Link from "next/link";
import type { Doc } from "@/lib/live";

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

export function SignupsSlot({ tournamentId, tournament, divisions, manager }: SignupsSlotProps) {
  const base = `/tournaments/${encodeURIComponent(tournamentId)}`;
  const captains = tournament.draftMode === "captains";
  return (
    <div className="card" data-slot="tournament-signups">
      <h2 className="card-title">Players</h2>
      <div className="home-actions">
        <Link className="btn btn-primary btn-small" href={`${base}/signups`}>
          {manager ? "Player signups" : "Sign up to play"}
        </Link>
      </div>
      {divisions.length > 0 && (
        <ul className="hosted-slot-links">
          {divisions.map((d) => (
            <li key={d.id}>
              {captains && <Link href={`${base}/draft/${encodeURIComponent(d.id)}`}>{divisionLabel(d)}: captains&apos; draft</Link>}
              {captains && " · "}
              <Link href={`${base}/team-draft/${encodeURIComponent(d.id)}`}>{divisionLabel(d)}: teams</Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
