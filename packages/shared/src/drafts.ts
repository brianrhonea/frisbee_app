// Players signing up as individuals, and the teams drafted from them:
// signups (tournaments/{t}/signups/{uid}), the balanced draft the host
// deals, the captains' live draft (tournaments/{t}/drafts/{division}) and
// a league's real teams made from the drafted ones.
//
// The pure logic is ported from firebase/functions/src/tournaments
// (draft_model.ts, league.ts) and the app's
// lib/domain/tournament_engine/team_builder.dart; the API and the website
// both use it. The functions keep their own copy while the app still calls
// the callables: change both together.
import { z } from "zod";
import { searchKeywords } from "./keywords.js";

// ---- Signups -----------------------------------------------------------------

export const signupStatuses = ["applied", "accepted", "waitlisted", "declined", "withdrawn"] as const;
export type SignupStatus = (typeof signupStatuses)[number];
export const signupStatusLabels: Record<SignupStatus, string> = {
  applied: "Signed up",
  accepted: "Accepted",
  waitlisted: "Waitlist",
  declined: "Declined",
  withdrawn: "Withdrawn",
};

export const genderMatches = ["mmp", "wmp"] as const;
export type GenderMatch = (typeof genderMatches)[number];
export const genderMatchLabels: Record<GenderMatch, string> = { mmp: "MMP", wmp: "WMP" };

/**
 * Signups by name, ignoring case, comparing code units as the app does
 * (PlayerSignup.compareByName): the order players are drafted in, so a
 * seed deals the same teams on the app and the website.
 */
export function signupOrder(a: { name: string; uid: string }, b: { name: string; uid: string }): number {
  const x = a.name.toLowerCase();
  const y = b.name.toLowerCase();
  // Equal names go by uid, so every sort gives one order.
  if (x !== y) return x < y ? -1 : 1;
  return a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0;
}

/** What the rules and the app allow (validSignup, PlayerSignup). */
export const signupLimits = { name: 100, divisionId: 100, minSkill: 1, maxSkill: 5, paymentNote: 200 } as const;

/** The app's hints under the skill slider (_skillHints). */
export const skillHints: Record<number, string> = {
  1: "New to ultimate",
  2: "Some experience",
  3: "Solid recreational player",
  4: "Experienced, plays regularly",
  5: "Competitive club or college level",
};

/** A signup as stored (PlayerSignup.toMap plus its timestamps). */
export interface PlayerSignupDoc {
  name: string;
  divisionId: string;
  skill: number;
  gender?: GenderMatch | null;
  status: SignupStatus;
  createdAt?: string;
  updatedAt?: string;
}

/** `PUT /v1/tournaments/:id/signups/me`: sign up, edit, or sign back up. The name comes from the account. */
export const saveSignupRequestSchema = z.strictObject({
  divisionId: z.string().min(1, "Pick a division.").max(signupLimits.divisionId),
  skill: z.number().int().min(signupLimits.minSkill, "Rate your skill from 1 to 5.").max(signupLimits.maxSkill, "Rate your skill from 1 to 5."),
  gender: z.enum(genderMatches).nullable().default(null),
});
export type SaveSignupInput = z.output<typeof saveSignupRequestSchema>;

/** `PUT /v1/tournaments/:id/signups/:uid/status`: the host decides, or the player withdraws. */
export const signupStatusRequestSchema = z.strictObject({ status: z.enum(signupStatuses) });

/** `PUT /v1/tournaments/:id/signups/:uid/payment`: the host marks a player paid (the note is kept). */
export const signupPaymentRequestSchema = z.strictObject({ paid: z.boolean() });

// ---- Drafted teams -------------------------------------------------------------

/** A team the host drafted: an item of `divisions/{id}.teams` (TournamentTeam). */
export interface DraftedTeam {
  id: string;
  name: string;
  captainId: string | null;
  playerIds: string[];
  playerNames: Record<string, string>;
}

/** Real team ids start with this, so everyone can tell they've been made. */
export const leagueTeamPrefix = "league_";

/** The same drafted team always gets the same id, so a retry can't double up. */
export const leagueTeamId = (tournamentId: string, draftId: string): string => `${leagueTeamPrefix}${tournamentId}_${draftId}`;

const clip = (s: unknown, max: number): string => (typeof s === "string" ? s.trim().slice(0, max) : "");
const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

/** The drafted teams stored on a division, as the app wrote them (draftTeams in league.ts). */
export function draftedTeams(raw: unknown): DraftedTeam[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(isRecord).map((t) => ({
    id: String(t.id ?? ""),
    name: clip(t.name, 80),
    captainId: typeof t.captainId === "string" ? t.captainId : null,
    playerIds: Array.isArray(t.playerIds) ? t.playerIds.map(String) : [],
    playerNames: Object.fromEntries(Object.entries(isRecord(t.playerNames) ? t.playerNames : {}).map(([k, v]) => [k, clip(v, 100)])),
  }));
}

/** Whether every drafted team already has its real team. */
export const teamsCreated = (teams: readonly DraftedTeam[]): boolean => teams.length > 0 && teams.every((t) => t.id.startsWith(leagueTeamPrefix));

/**
 * A division's seeds and captains with [teams] in place of the drafted
 * teams it had ([before], in order). Teams that registered on their own
 * keep their seeds and captains. A drafted team replaced by one at the
 * same position keeps its seed.
 */
export function withDrafted(
  division: { seeds?: unknown; captains?: unknown },
  before: readonly string[],
  teams: readonly { id: string; captainId?: string | null }[],
): { seeds: string[]; captains: Record<string, string[]> } {
  const fresh = teams.map((t) => t.id);
  const seeds = Array.isArray(division.seeds) ? division.seeds.filter((s): s is string => typeof s === "string") : [];
  const out: string[] = [];
  const used = new Set<string>();
  for (const s of seeds) {
    const i = before.indexOf(s);
    if (i >= 0) {
      if (i < fresh.length && !used.has(fresh[i])) {
        out.push(fresh[i]);
        used.add(fresh[i]);
      }
    } else if (!fresh.includes(s) && !out.includes(s)) {
      out.push(s);
    }
  }
  for (const f of fresh) if (!used.has(f)) out.push(f);
  const old = isRecord(division.captains) ? division.captains : {};
  const captains: Record<string, string[]> = {};
  for (const [id, uids] of Object.entries(old)) {
    if (!before.includes(id) && !fresh.includes(id) && Array.isArray(uids)) {
      captains[id] = uids.filter((u): u is string => typeof u === "string");
    }
  }
  for (const t of teams) captains[t.id] = t.captainId ? [t.captainId] : [];
  return { seeds: out, captains };
}

/** The seeds of teams that registered on their own (TournamentDivision.registeredSeeds). */
export function registeredSeeds(division: { seeds?: unknown; teams?: unknown }): string[] {
  const drafted = new Set(draftedTeams(division.teams).map((t) => t.id));
  return (Array.isArray(division.seeds) ? division.seeds : []).filter((s): s is string => typeof s === "string" && !drafted.has(s));
}

/** `PUT /v1/tournaments/:id/divisions/:div/drafted-teams`: the host saves the teams they dealt or adjusted. */
export const saveDraftedTeamsRequestSchema = z.strictObject({
  teams: z
    .array(
      z.strictObject({
        id: z
          .string()
          .min(1)
          .max(100)
          .regex(/^[A-Za-z0-9_-]+$/, "Invalid team id.")
          // Real league teams' ids: only createLeagueTeams makes those.
          .refine((id) => !id.startsWith(leagueTeamPrefix), "Invalid team id."),
        name: z.string().max(80),
        captainId: z.string().min(1).max(128).nullable().default(null),
        playerIds: z.array(z.string().min(1).max(128)).max(200),
        playerNames: z.record(z.string().max(128), z.string().max(100)),
      }),
    )
    .max(32),
});
export type SaveDraftedTeamsInput = z.output<typeof saveDraftedTeamsRequestSchema>;

/**
 * Why the host can't save [teams] now, or null: the checks the app's team
 * draft makes before saving (TeamDraftViewModel._save).
 */
export function draftedTeamsProblem(args: {
  division: { maxTeams?: unknown; seeds?: unknown; teams?: unknown };
  teams: readonly DraftedTeam[];
  /** The schedule is published (the division has games). */
  locked: boolean;
}): string | null {
  const { division, teams, locked } = args;
  const saved = draftedTeams(division.teams);
  if (teamsCreated(saved)) return "The league's teams are made. Manage rosters on each team.";
  if (locked) {
    const a = teams.map((t) => t.id).sort();
    const b = saved.map((t) => t.id).sort();
    if (a.length !== b.length || a.some((id, i) => id !== b[i])) return "The schedule is published, so teams can only be adjusted.";
  }
  if (teams.length < 2) return "Make at least two teams.";
  const reg = registeredSeeds(division).length;
  const max = typeof division.maxTeams === "number" ? division.maxTeams : 16;
  if (teams.length + reg > max) {
    return `This division takes up to ${max} teams${reg === 0 ? "" : `, and ${reg} registered on their own`}. Raise the cap or draft fewer teams.`;
  }
  const empty = teams.find((t) => t.playerIds.length === 0);
  if (empty) return `${empty.name} has no players.`;
  if (teams.some((t) => t.name.trim() === "")) return "Every team needs a name.";
  const names = teams.map((t) => t.name.trim().toLowerCase());
  if (new Set(names).size !== names.length) return "Team names must be different.";
  if (new Set(teams.map((t) => t.id)).size !== teams.length) return "A team is listed twice.";
  const seen = new Set<string>();
  for (const t of teams) for (const p of t.playerIds) {
    if (seen.has(p)) return "A player is on more than one team.";
    seen.add(p);
  }
  return null;
}

/** What saving writes for each team: a trimmed name, and its first player as captain if it has none. */
export const normalizedTeam = (t: DraftedTeam): DraftedTeam => {
  const captainId = t.captainId && t.playerIds.includes(t.captainId) ? t.captainId : (t.playerIds[0] ?? null);
  return {
    id: t.id,
    name: t.name.trim(),
    captainId,
    playerIds: [...t.playerIds],
    playerNames: Object.fromEntries(t.playerIds.map((p) => [p, clip(t.playerNames[p], 100) || "Player"])),
  };
};

// ---- The balanced draft (team_builder.dart) --------------------------------------

/** A signed-up player to draft. */
export interface DraftPlayer {
  uid: string;
  name: string;
  skill: number;
  gender: GenderMatch | null;
}

/** A small seeded generator (mulberry32), so the same seed deals the same teams. */
export function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function shuffle<T>(list: T[], random: () => number): T[] {
  for (let i = list.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [list[i], list[j]] = [list[j], list[i]];
  }
  return list;
}

/**
 * Drafts [players] onto [teams], replacing their rosters, so teams come out
 * even in size and total skill: strongest first, each to the team with the
 * fewest players and then the lowest skill total. With [mixed], each gender
 * match is dealt as its own group, players with none last. [seed] only
 * breaks ties between equally skilled players. Each captain is the team's
 * most skilled player.
 */
export function balancedDraft(players: readonly DraftPlayer[], teams: readonly DraftedTeam[], opts: { seed: number; mixed?: boolean }): DraftedTeam[] {
  if (teams.length === 0) return [];
  const unique = shuffle([...new Map(players.map((p) => [p.uid, p])).values()], seededRandom(opts.seed));
  const order = new Map(unique.map((p, i) => [p.uid, i]));
  unique.sort((a, b) => b.skill - a.skill || order.get(a.uid)! - order.get(b.uid)!);
  const rosters = teams.map(() => [] as DraftPlayer[]);
  const skill = teams.map(() => 0);
  const mixed = opts.mixed === true;
  const groups: Array<GenderMatch | null> = mixed ? ["mmp", "wmp", null] : [null];
  for (const group of groups) {
    const members = mixed ? unique.filter((p) => p.gender === group) : unique;
    const inGroup = teams.map(() => 0);
    for (const p of members) {
      let best = 0;
      for (let t = 1; t < teams.length; t++) {
        const byGroup = mixed && group !== null ? inGroup[t] - inGroup[best] : 0;
        const bySize = rosters[t].length - rosters[best].length;
        const bySkill = skill[t] - skill[best];
        const better = byGroup !== 0 ? byGroup < 0 : bySize !== 0 ? bySize < 0 : bySkill < 0;
        if (better) best = t;
      }
      rosters[best].push(p);
      inGroup[best]++;
      skill[best] += p.skill;
    }
  }
  return teams.map((t, i) => {
    let top: DraftPlayer | null = null;
    for (const p of rosters[i]) if (!top || p.skill > top.skill) top = p;
    return {
      ...t,
      captainId: top?.uid ?? null,
      playerIds: rosters[i].map((p) => p.uid),
      playerNames: Object.fromEntries(rosters[i].map((p) => [p.uid, p.name])),
    };
  });
}

/** [count] empty teams "Team n", ids continuing after any in [existing]. */
export function blankTeams(count: number, existing: readonly DraftedTeam[] = []): DraftedTeam[] {
  let next = existing.length + 1;
  const taken = new Set(existing.map((t) => t.id));
  const out: DraftedTeam[] = [];
  for (let i = 0; i < count; i++) {
    while (taken.has(`team${next}`)) next++;
    const id = `team${next}`;
    taken.add(id);
    out.push({ id, name: `Team ${next++}`, captainId: null, playerIds: [], playerNames: {} });
  }
  return out;
}

/**
 * Moves [player] onto [teamId] (off any other team), or off every team when
 * [teamId] is null. A captain who moves stops being captain; a team left
 * without one gets its first player.
 */
export function movePlayer(teams: readonly DraftedTeam[], player: { uid: string; name: string }, teamId: string | null): DraftedTeam[] {
  return teams.map((t) => {
    if (t.id === teamId && !t.playerIds.includes(player.uid)) {
      return {
        ...t,
        playerIds: [...t.playerIds, player.uid],
        playerNames: { ...t.playerNames, [player.uid]: player.name },
        captainId: t.captainId ?? player.uid,
      };
    }
    if (t.id !== teamId && t.playerIds.includes(player.uid)) {
      const ids = t.playerIds.filter((p) => p !== player.uid);
      const names = { ...t.playerNames };
      delete names[player.uid];
      return { ...t, playerIds: ids, playerNames: names, captainId: t.captainId === player.uid ? (ids[0] ?? null) : t.captainId };
    }
    return t;
  });
}

/** Teams to start with: about one and a half fields of players each (suggestedTeamCount). */
export function suggestedTeamCount(players: number, playersOnField: number, maxTeams: number): number {
  const perTeam = Math.round(playersOnField * 1.5) || 1;
  return Math.min(Math.max(Math.round(players / perTeam), 2), Math.max(maxTeams, 2));
}

// ---- The captains' live draft (draft_model.ts) ------------------------------------

export const draftStatuses = ["live", "paused", "done", "finished"] as const;
export type DraftStatus = (typeof draftStatuses)[number];

export interface DraftPick {
  uid: string;
  captainId: string;
}

/** A player in the pool; skill and gender stay in the private details doc. */
export interface PoolPlayer {
  uid: string;
  name: string;
  skill: number;
  gender: GenderMatch | null;
}

/** `tournaments/{t}/drafts/{division}` as stored. */
export interface LiveDraftDoc {
  status: DraftStatus;
  captains: { uid: string; name: string }[];
  captainIds: string[];
  pool: Record<string, string>;
  picks: DraftPick[];
  pickSeconds: number;
  mixed: boolean;
  turnStartedAt?: string | null;
  startedBy?: string;
}

/** `drafts/{division}/details/pool`: skill and gender for the host and the captains. */
export interface DraftDetailsDoc {
  players: Record<string, { skill?: number; gender?: GenderMatch | null }>;
}

export const draftLimits = { minCaptains: 2, maxCaptains: 16, maxPool: 200, maxPickSeconds: 600 } as const;
export const minCaptains = draftLimits.minCaptains;
export const maxCaptains = draftLimits.maxCaptains;
export const maxPool = draftLimits.maxPool;

/** Which captain (an index into the order) makes pick number [pick]: the order snakes. */
export function snakeIndex(captains: number, pick: number): number {
  const round = Math.floor(pick / captains);
  const spot = pick % captains;
  return round % 2 === 0 ? spot : captains - 1 - spot;
}

/** Whose turn it is, or null once every player has been picked. */
export function onTheClock(captainIds: readonly string[], picks: readonly DraftPick[], poolSize: number): string | null {
  if (captainIds.length === 0 || picks.length >= poolSize) return null;
  return captainIds[snakeIndex(captainIds.length, picks.length)];
}

/** The players nobody has picked yet. */
export function available<T extends { uid: string }>(pool: readonly T[], picks: readonly DraftPick[]): T[] {
  const taken = new Set(picks.map((p) => p.uid));
  return pool.filter((p) => !taken.has(p.uid));
}

/**
 * Who a captain who ran out of time gets: the best player left, and in a
 * mixed division the best of the gender match the team has fewer of. Ties
 * go to the lower uid.
 */
export function autoPick(left: readonly PoolPlayer[], team: readonly PoolPlayer[], mixed: boolean): PoolPlayer | null {
  if (left.length === 0) return null;
  const best = (list: readonly PoolPlayer[]) => [...list].sort((a, b) => b.skill - a.skill || (a.uid < b.uid ? -1 : 1))[0];
  if (mixed) {
    const count = (g: GenderMatch) => team.filter((p) => p.gender === g).length;
    const want: GenderMatch = count("mmp") <= count("wmp") ? "mmp" : "wmp";
    const ofWant = left.filter((p) => p.gender === want);
    if (ofWant.length > 0) return best(ofWant);
  }
  return best(left);
}

/** Why [uid] can't be picked now, or null. */
export function pickProblem(args: {
  status: string;
  captainIds: readonly string[];
  picks: readonly DraftPick[];
  pool: readonly { uid: string }[];
  uid: string;
}): string | null {
  const { status, captainIds, picks, pool, uid } = args;
  if (status === "paused") return "The draft is paused.";
  if (status !== "live") return "The draft isn't running.";
  if (!pool.some((p) => p.uid === uid)) return "That player isn't in the draft.";
  if (picks.some((p) => p.uid === uid)) return "That player has already been picked.";
  if (onTheClock(captainIds, picks, pool.length) === null) return "Every player has been picked.";
  return null;
}

/** Why a draft can't start, or null: 2–16 accepted captains, and enough players for each to pick one. */
export function startProblem(args: { captainIds: readonly string[]; accepted: ReadonlySet<string>; poolSize: number }): string | null {
  const { captainIds, accepted, poolSize } = args;
  if (new Set(captainIds).size !== captainIds.length) return "A captain is listed twice.";
  if (captainIds.length < minCaptains) return `Pick at least ${minCaptains} captains.`;
  if (captainIds.length > maxCaptains) return `A draft takes at most ${maxCaptains} captains.`;
  if (captainIds.some((c) => !accepted.has(c))) return "Every captain has to be an accepted player.";
  if (poolSize < captainIds.length) return "There aren't enough players for every captain to pick.";
  if (poolSize > maxPool) return `A draft takes at most ${maxPool} players.`;
  return null;
}

/** The drafted teams: each captain first on their own team, then their picks in order. */
export function teamsFromDraft(args: {
  captains: readonly { uid: string; name: string }[];
  picks: readonly DraftPick[];
  names: Readonly<Record<string, string>>;
  teamNames?: Readonly<Record<string, string>>;
}): DraftedTeam[] {
  const { captains, picks, names, teamNames = {} } = args;
  return captains.map((c, i) => {
    const playerIds = [c.uid, ...picks.filter((p) => p.captainId === c.uid).map((p) => p.uid)];
    return {
      id: `team${i + 1}`,
      name: teamNames[c.uid] || `Team ${c.name}`.slice(0, 80),
      captainId: c.uid,
      playerIds,
      playerNames: Object.fromEntries(playerIds.map((id) => [id, id === c.uid ? c.name : (names[id] ?? "Player")])),
    };
  });
}

/** [captainId]'s team so far: the captain, then their picks in order (LiveDraft.teamOf). */
export const draftTeamOf = (picks: readonly DraftPick[], captainId: string): string[] => [
  captainId,
  ...picks.filter((p) => p.captainId === captainId).map((p) => p.uid),
];

/** Seconds left on the clock at [now], or null with no limit or nobody picking (LiveDraft.secondsLeft). */
export function draftSecondsLeft(d: Pick<LiveDraftDoc, "pickSeconds" | "status" | "turnStartedAt">, now: number): number | null {
  if (!(d.pickSeconds > 0) || d.status !== "live" || !d.turnStartedAt) return null;
  const started = Date.parse(d.turnStartedAt);
  if (Number.isNaN(started)) return null;
  return Math.max(0, d.pickSeconds - Math.floor((now - started) / 1000));
}

export const draftControlActions = ["pause", "resume", "undo", "autopick", "cancel"] as const;
export type DraftControlAction = (typeof draftControlActions)[number];

/** `POST /v1/tournaments/:id/divisions/:div/draft`: the host starts it. pickSeconds is clamped to 0–600, as the callable does. */
export const startDraftRequestSchema = z.strictObject({
  captainIds: z.array(z.string().min(1).max(128)).max(64),
  pickSeconds: z
    .number()
    .finite()
    .default(0)
    .transform((n) => Math.min(draftLimits.maxPickSeconds, Math.max(0, Math.floor(n)))),
});
export const draftPickRequestSchema = z.strictObject({ uid: z.string().max(128) });
export const draftControlRequestSchema = z.strictObject({
  action: z.string().refine((a) => (draftControlActions as readonly string[]).includes(a), "Unknown action."),
});

// ---- A league's real teams (league.ts) ----------------------------------------------

/**
 * Why teams can't be created now, or null: only leagues where players sign
 * up, before the schedule, two or more teams each with players and a
 * captain on it, and every player accepted and on one team.
 */
export function leagueProblem(args: {
  tournament: Record<string, unknown> | undefined | null;
  division: Record<string, unknown> | undefined | null;
  teams: readonly DraftedTeam[];
  accepted: ReadonlySet<string>;
  hasGames: boolean;
}): string | null {
  const { tournament, division, teams, accepted, hasGames } = args;
  if (!tournament || !division) return "That league or division doesn't exist.";
  if (tournament.kind !== "league" || tournament.entryType !== "players") return "Only leagues where players sign up draft teams.";
  if (hasGames) return "The schedule is published. Create the teams before publishing it.";
  if (teams.length < 2) return "Draft at least two teams first.";
  const seen = new Set<string>();
  for (const team of teams) {
    if (!team.id || !team.name) return "Every team needs a name.";
    if (team.playerIds.length === 0) return `${team.name} has no players.`;
    if (!team.captainId || !team.playerIds.includes(team.captainId)) return `${team.name} needs a captain from its players.`;
    for (const p of team.playerIds) {
      if (seen.has(p)) return "A player is on more than one team.";
      seen.add(p);
      if (!accepted.has(p)) return `${team.playerNames[p] || "A player"} isn't accepted for this division.`;
    }
  }
  return null;
}

/** "Reds - Thursday Night", within a team name's 80 characters. */
export function leagueTeamName(team: string, league: string): string {
  const suffix = ` - ${clip(league, 30)}`;
  return `${clip(team, 80 - suffix.length)}${suffix}`;
}

/** The new team's doc: the captain owns it, everyone else is a player (teamDoc). */
export function leagueTeamDoc<T>(args: {
  team: DraftedTeam;
  tournamentId: string;
  tournament: Record<string, unknown>;
  division: Record<string, unknown>;
  city: string;
  createdAt: T;
}): Record<string, unknown> {
  const { team, tournamentId, tournament, division, city, createdAt } = args;
  const captain = team.captainId as string;
  const players = team.playerIds.filter((p) => p !== captain);
  const name = (uid: string) => (Object.hasOwn(team.playerNames, uid) && team.playerNames[uid]) || "Player";
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
    leagueId: tournamentId,
    leagueHostId: tournament.hostId ?? null,
  };
}

/** The new team's directory listing (`teamDirectory/{teamId}`). */
export function leagueDirectoryDoc(team: Record<string, unknown>): Record<string, unknown> {
  return {
    name: team.name,
    division: team.division,
    level: team.level,
    city: team.city,
    keywords: searchKeywords(`${String(team.name)} ${String(team.city)}`),
  };
}

const everyoneAccess = () => ({ readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [] as string[], writeUsers: [] as string[] });

/** The chat a new team starts with: General, and a Voice Channels folder with three rooms (defaultChat). */
export function leagueTeamChat<T>(uid: string, createdAt: T): { rooms: Record<string, Record<string, unknown>>; folders: Record<string, Record<string, unknown>> } {
  const made = { createdBy: uid, createdAt };
  const voice = [
    ["voice-lounge", "Lounge"],
    ["voice-sideline", "Sideline"],
    ["voice-film", "Film Room"],
  ];
  return {
    rooms: {
      general: { name: "General", ...everyoneAccess(), folderId: null, position: 0, kind: "text", ...made },
      ...Object.fromEntries(voice.map(([id, name], i) => [id, { name, ...everyoneAccess(), folderId: "voice", position: i, kind: "voice", ...made }])),
    },
    folders: { voice: { name: "Voice Channels", position: 1000, ...everyoneAccess(), ...made } },
  };
}

/** The team's accepted entry in the league, its captain reporting scores. */
export function leagueEntry<T>(team: DraftedTeam, divisionId: string, updatedAt: T): Record<string, unknown> {
  return { teamName: team.name, divisionId, status: "accepted", captainIds: team.captainId ? [team.captainId] : [], updatedAt };
}

/** The division's drafted teams, seeds and captains once they have real ids. */
export function madeTeams(
  teams: readonly DraftedTeam[],
  tournamentId: string,
  division: { seeds?: unknown; captains?: unknown } = {},
): { teams: DraftedTeam[]; seeds: string[]; captains: Record<string, string[]> } {
  const real = teams.map((t) => ({ ...t, id: leagueTeamId(tournamentId, t.id) }));
  const merged = withDrafted(division, teams.map((t) => t.id), real);
  return {
    teams: real.map((t) => ({ id: t.id, name: t.name, captainId: t.captainId, playerIds: t.playerIds, playerNames: t.playerNames })),
    ...merged,
  };
}

// ---- Endpoints --------------------------------------------------------------------

const enc = encodeURIComponent;
/** The API paths this slice adds. */
export const draftPaths = {
  mySignup: (t: string) => `/v1/tournaments/${enc(t)}/signups/me`,
  signupStatus: (t: string, uid: string) => `/v1/tournaments/${enc(t)}/signups/${enc(uid)}/status`,
  signupPayment: (t: string, uid: string) => `/v1/tournaments/${enc(t)}/signups/${enc(uid)}/payment`,
  draftedTeams: (t: string, d: string) => `/v1/tournaments/${enc(t)}/divisions/${enc(d)}/drafted-teams`,
  leagueTeams: (t: string, d: string) => `/v1/tournaments/${enc(t)}/divisions/${enc(d)}/league-teams`,
  draft: (t: string, d: string) => `/v1/tournaments/${enc(t)}/divisions/${enc(d)}/draft`,
  draftPicks: (t: string, d: string) => `/v1/tournaments/${enc(t)}/divisions/${enc(d)}/draft/picks`,
  draftControl: (t: string, d: string) => `/v1/tournaments/${enc(t)}/divisions/${enc(d)}/draft/control`,
  draftFinish: (t: string, d: string) => `/v1/tournaments/${enc(t)}/divisions/${enc(d)}/draft/finish`,
};
