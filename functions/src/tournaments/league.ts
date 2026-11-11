// Leagues where players sign up (see lib/domain/models/hosted_tournament.dart):
// the host drafts teams from accepted signups, then `createLeagueTeams`
// turns each drafted team into a real team: the captain owns it, the other
// players are its members, and it gets chat rooms and a place on the
// league's entries. Everything here is pure so it can be tested; the
// callable in callables.ts does the reads and the one batch write.

import { withDrafted } from "./draft_model";

export type Data = Record<string, unknown>;

/** A team the host drafted: `divisions/{id}.teams` in the app. */
export interface DraftTeam {
  id: string;
  name: string;
  captainId: string | null;
  playerIds: string[];
  playerNames: Record<string, string>;
}

/** Real team ids start with this, so the app can tell they've been made. */
export const leagueTeamPrefix = "league_";

/** The same drafted team always gets the same id, so a retry can't double up. */
export const leagueTeamId = (tournamentId: string, draftId: string): string =>
  `${leagueTeamPrefix}${tournamentId}_${draftId}`;

const clip = (s: unknown, max: number): string => (typeof s === "string" ? s.trim().slice(0, max) : "");

/**
 * Whether [uid] can manage events on [team]: the same check as `can(team,
 * 'manageEvents')` in firestore.rules. Owners and the older coach and
 * captain tiers can; other members need the permission through a role.
 */
export function canManageEvents(team: Data | undefined, uid: string): boolean {
  if (!team) return false;
  const members = (team.members ?? {}) as Record<string, string>;
  if (["owner", "coach", "captain"].includes(members[uid])) return true;
  const ids = (team.memberIds ?? []) as string[];
  const perms = ((team.memberPerms ?? {}) as Record<string, string[]>)[uid] ?? [];
  return ids.includes(uid) && perms.includes("manageEvents");
}

/** The drafted teams stored on a division, as the app wrote them. */
export function draftTeams(raw: unknown): DraftTeam[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((t): t is Data => typeof t === "object" && t !== null)
    .map((t) => ({
      id: String(t.id ?? ""),
      name: clip(t.name, 80),
      captainId: typeof t.captainId === "string" ? t.captainId : null,
      playerIds: Array.isArray(t.playerIds) ? t.playerIds.map(String) : [],
      playerNames: Object.fromEntries(
        Object.entries((t.playerNames ?? {}) as Record<string, unknown>).map(([k, v]) => [k, clip(v, 100)]),
      ),
    }));
}

/** Whether every drafted team already has its real team (a retry). */
export const teamsCreated = (teams: DraftTeam[]): boolean =>
  teams.length > 0 && teams.every((t) => t.id.startsWith(leagueTeamPrefix));

/**
 * Why teams can't be created now, or null. Teams have to be set before
 * the schedule is published, since games refer to their ids, and every
 * player has to be accepted: the server doesn't trust the draft the app
 * wrote.
 */
export function leagueProblem(args: {
  tournament: Data | undefined;
  division: Data | undefined;
  teams: DraftTeam[];
  accepted: ReadonlySet<string>;
  hasGames: boolean;
}): string | null {
  const { tournament, division, teams, accepted, hasGames } = args;
  if (!tournament || !division) return "That league or division doesn't exist.";
  if (tournament.kind !== "league" || tournament.entryType !== "players") {
    return "Only leagues where players sign up draft teams.";
  }
  if (hasGames) return "The schedule is published. Create the teams before publishing it.";
  if (teams.length < 2) return "Draft at least two teams first.";
  const seen = new Set<string>();
  for (const team of teams) {
    if (!team.id || !team.name) return "Every team needs a name.";
    if (team.playerIds.length === 0) return `${team.name} has no players.`;
    if (!team.captainId || !team.playerIds.includes(team.captainId)) {
      return `${team.name} needs a captain from its players.`;
    }
    for (const p of team.playerIds) {
      if (seen.has(p)) return "A player is on more than one team.";
      seen.add(p);
      if (!accepted.has(p)) return `${team.playerNames[p] || "A player"} isn't accepted for this division.`;
    }
  }
  return null;
}

/**
 * "Reds - Thursday Night", kept inside a team name's 80 characters. A dash,
 * not brackets, so search (which splits words at spaces and dashes) finds
 * the team by its league's name too.
 */
export function leagueTeamName(team: string, league: string): string {
  const suffix = ` - ${clip(league, 30)}`;
  return `${clip(team, 80 - suffix.length)}${suffix}`;
}

/** The new team's doc: the captain owns it, everyone else is a player. */
export function teamDoc(args: {
  team: DraftTeam;
  tournamentId: string;
  tournament: Data;
  division: Data;
  city: string;
  createdAt: unknown;
}): Data {
  const { team, tournamentId, tournament, division, city, createdAt } = args;
  const captain = team.captainId as string;
  const players = team.playerIds.filter((p) => p !== captain);
  const name = (uid: string) => team.playerNames[uid] || "Player";
  return {
    name: leagueTeamName(team.name, String(tournament.name ?? "League")),
    division: division.division ?? "mixed",
    level: "league",
    city,
    ownerId: captain,
    members: { [captain]: "owner", ...Object.fromEntries(players.map((p) => [p, "player"])) },
    memberIds: [captain, ...players],
    memberNames: { [captain]: name(captain), ...Object.fromEntries(players.map((p) => [p, name(p)])) },
    createdAt,
    // Marks it as a league's team: its captain can't delete it mid-season.
    leagueId: tournamentId,
    leagueHostId: tournament.hostId ?? null,
  };
}

/** `searchKeywords` in lib/domain/models/model_utils.dart: word prefixes. */
export function searchKeywords(text: string): string[] {
  const words = text
    .toLowerCase()
    .split(/[\s\-_.]+/)
    .filter((w) => w.length > 0);
  const out = new Set<string>();
  for (const w of words) {
    for (let i = 1; i <= Math.min(w.length, 20); i++) out.add(w.slice(0, i));
  }
  return [...out].slice(0, 100);
}

/** The new team's public directory listing (`teamDirectory/{teamId}`). */
export function directoryDoc(team: Data): Data {
  return {
    name: team.name,
    division: team.division,
    level: team.level,
    city: team.city,
    keywords: searchKeywords(`${team.name} ${team.city}`),
  };
}

const everyone = { readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [], writeUsers: [] };

/**
 * Chat a new team starts with, like `_newTeamBatch` in the app: a General
 * room and a Voice Channels folder with three voice rooms.
 */
export function defaultChat(uid: string, createdAt: unknown): { rooms: Record<string, Data>; folders: Record<string, Data> } {
  const made = { createdBy: uid, createdAt };
  const voice = [
    ["voice-lounge", "Lounge"],
    ["voice-sideline", "Sideline"],
    ["voice-film", "Film Room"],
  ];
  return {
    rooms: {
      general: { name: "General", ...everyone, folderId: null, position: 0, kind: "text", ...made },
      ...Object.fromEntries(
        voice.map(([id, name], i) => [id, { name, ...everyone, folderId: "voice", position: i, kind: "voice", ...made }]),
      ),
    },
    folders: { voice: { name: "Voice Channels", position: 1000, ...everyone, ...made } },
  };
}

/**
 * The team's entry in the league: already accepted, its captain reports
 * scores. It keeps the host's short team name ("Reds"); only the team's own
 * doc carries the league's name too.
 */
export function leagueEntry(team: DraftTeam, divisionId: string, updatedAt: unknown): Data {
  return {
    teamName: team.name,
    divisionId,
    status: "accepted",
    captainIds: team.captainId ? [team.captainId] : [],
    updatedAt,
  };
}

/**
 * The division's drafted teams, seeds and captains once they have real
 * ids. Teams that registered on their own keep their seeds and captains.
 */
export function madeTeams(
  teams: DraftTeam[],
  tournamentId: string,
  division: Data = {},
): {
  teams: Data[];
  seeds: string[];
  captains: Record<string, string[]>;
} {
  const real = teams.map((t) => ({ ...t, id: leagueTeamId(tournamentId, t.id) }));
  const merged = withDrafted(
    division,
    teams.map((t) => t.id),
    real,
  );
  return {
    teams: real.map((t) => ({
      id: t.id,
      name: t.name,
      captainId: t.captainId,
      playerIds: t.playerIds,
      playerNames: t.playerNames,
    })),
    ...merged,
  };
}
