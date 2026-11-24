// What signed-out visitors see of hosted tournaments and leagues
// (`GET /v1/public/tournaments`, `/v1/public/tournaments/:id`) and of a
// community group's tournament (`/v1/public/group-tournaments/:groupId/:id`):
// the overview, the teams playing, the schedule and the scores. Never who
// signed up, captains, contact or payment details, or player names; the
// API builds each answer field by field (apps/api/src/tournaments/public.ts).
import { z } from "zod";
import type { TournamentSpots } from "./discover.js";
import type { GroupTournamentListing } from "./group_tournaments.js";
import type {
  DivisionSummaryDoc,
  GameDoc,
  HostedKind,
  HostedStatus,
  SeasonDoc,
  SettingsDoc,
  TournamentDoc,
  TournamentEntryType,
  TournamentVisibility,
  DraftMode,
} from "./tournaments.js";
import type { CompetitionLevel, Division } from "./team.js";

/** A fee as visitors see it: the amount only (instructions often hold a payment handle or phone number). */
export interface PublicFee {
  amountCents: number;
  currency: string;
  dueAt: string | null;
}

/** A tournament or league in the list (HostedTournamentCard's fields). */
export interface PublicHostedCard {
  id: string;
  hostId: string;
  hostName: string;
  hostKind: TournamentDoc["hostKind"];
  hostOfficial: boolean;
  name: string;
  startsOn: string;
  endsOn: string | null;
  location: string;
  visibility: TournamentVisibility;
  entryType: TournamentEntryType;
  teamEntry: boolean;
  kind: HostedKind;
  status: HostedStatus;
  bidFee: PublicFee | null;
  divisions: DivisionSummaryDoc[];
  /** In the list only: the event's games being played now (isLiveGame), for Discover's "Live now". */
  liveGames?: PublicLiveGame[];
  /** In the list only: team spots left while registration is open (tournamentSpots in discover.ts); absent otherwise. */
  spots?: TournamentSpots;
}

/** A game being played now, as Discover's "Live now" card shows it: the teams' public names and the running score. */
export interface PublicLiveGame {
  divisionId: string;
  gameId: string;
  label: string;
  field: number;
  teamA: string;
  teamB: string;
  nameA: string;
  nameB: string;
  scoreA: number;
  scoreB: number;
  updatedAt: string;
}

/** The overview: the card's fields and the rest of the Details card. */
export interface PublicHostedTournament extends PublicHostedCard {
  description: string;
  teamFee: PublicFee | null;
  season: SeasonDoc | null;
  draftMode: DraftMode;
  /** The tournament director's name; members read their email and phone from the event. */
  directorName: string | null;
  /** When rosters and fees are due (effectiveDeadline), ISO; null without one. */
  entryDeadline: string | null;
}

/** A division: format, seeds and places. Drafted teams carry only their id and name. */
export interface PublicHostedDivision {
  id: string;
  division: Division;
  level: CompetitionLevel;
  settings: SettingsDoc;
  maxTeams: number;
  minRoster: number | null;
  seeds: string[];
  placements: string[];
  teams: Array<{ id: string; name: string }>;
}

/** An accepted team's entry: its id (the team's), name and division. */
export interface PublicHostedEntry {
  id: string;
  teamName: string;
  divisionId: string;
  status: "accepted";
}

/** A game; its `live` running score never carries who updated it. */
export type PublicHostedGame = GameDoc & { id: string };

/** `GET /v1/public/tournaments`: upcoming and running published events, soonest first. */
export interface PublicHostedList {
  tournaments: PublicHostedCard[];
}

/** `GET /v1/public/tournaments/:id?division=`: the page, with one division's games. */
export interface PublicHostedPage {
  tournament: PublicHostedTournament;
  /** In the tournament's order. */
  divisions: PublicHostedDivision[];
  /** Accepted teams only. */
  entries: PublicHostedEntry[];
  /** Names of every team the seeds, places and games refer to. */
  names: Record<string, string>;
  /** The division [games] belong to (the asked-for one, else the first). */
  divisionId: string | null;
  /** That division's games, in order. */
  games: PublicHostedGame[];
}

/** `GET /v1/public/group-tournaments/:groupId/:id`: the public listing outsiders see. */
export type PublicGroupTournament = GroupTournamentListing;

const idPattern = /^[A-Za-z0-9_-]{1,128}$/;

/** The page's query: `?division=` picks whose games come back. */
export const publicHostedQuerySchema = z.object({
  division: z.string().regex(idPattern).optional().catch(undefined),
});

/**
 * A drafted team's name as visitors see it: always "Team N" (its place in
 * the division), whatever the host or the draft called it, since a
 * captains' draft names teams after their captains ("Team Alex"). When
 * another team in the event is already called that ([taken]), "Team N
 * (drafted)".
 */
export function publicDraftedName(index: number, taken: ReadonlySet<string> = new Set()): string {
  const name = `Team ${index + 1}`;
  const lower = new Set([...taken].map((n) => n.trim().toLowerCase()));
  return lower.has(name.toLowerCase()) ? `${name} (drafted)` : name;
}
