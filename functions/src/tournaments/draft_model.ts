// The captains' live draft (see draft.ts for the callables). Everything
// here is pure so it can be tested; lib/domain/models/live_draft.dart
// mirrors `snakeIndex` and `onTheClock`, and both sides share the same
// table of expected turns.

import type { DraftTeam } from "./league";

export type Gender = "mmp" | "wmp";

/** A player in the pool; skill and gender stay in the private details doc. */
export interface PoolPlayer {
  uid: string;
  name: string;
  skill: number;
  gender: Gender | null;
}

export interface Pick {
  uid: string;
  captainId: string;
}

export const minCaptains = 2;
export const maxCaptains = 16;
export const maxPool = 200;

/**
 * Which captain (an index into the draft order) makes pick number [pick]
 * (from 0): the order snakes, so the last captain of a round also opens
 * the next one.
 */
export function snakeIndex(captains: number, pick: number): number {
  const round = Math.floor(pick / captains);
  const spot = pick % captains;
  return round % 2 === 0 ? spot : captains - 1 - spot;
}

/** Whose turn it is, or null once every player has been picked. */
export function onTheClock(captainIds: readonly string[], picks: readonly Pick[], poolSize: number): string | null {
  if (captainIds.length === 0 || picks.length >= poolSize) return null;
  return captainIds[snakeIndex(captainIds.length, picks.length)];
}

/** The players nobody has picked yet. */
export function available(pool: readonly PoolPlayer[], picks: readonly Pick[]): PoolPlayer[] {
  const taken = new Set(picks.map((p) => p.uid));
  return pool.filter((p) => !taken.has(p.uid));
}

/**
 * Who a captain who ran out of time gets: the best player left, and in a
 * mixed division the best of whichever gender match the captain has fewer
 * of, so the team stays even. Ties go to the lower uid so it's stable.
 */
export function autoPick(
  left: readonly PoolPlayer[],
  team: readonly PoolPlayer[],
  mixed: boolean,
): PoolPlayer | null {
  if (left.length === 0) return null;
  const best = (list: readonly PoolPlayer[]) =>
    [...list].sort((a, b) => b.skill - a.skill || (a.uid < b.uid ? -1 : 1))[0];
  if (mixed) {
    const count = (g: Gender) => team.filter((p) => p.gender === g).length;
    const want: Gender = count("mmp") <= count("wmp") ? "mmp" : "wmp";
    const ofWant = left.filter((p) => p.gender === want);
    if (ofWant.length > 0) return best(ofWant);
  }
  return best(left);
}

/** Why [uid] can't be picked now, or null. */
export function pickProblem(args: {
  status: string;
  captainIds: readonly string[];
  picks: readonly Pick[];
  pool: readonly PoolPlayer[];
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

/**
 * Why a draft can't start, or null: two to sixteen captains, each an
 * accepted player of the division, and enough players left for each
 * captain to pick at least one.
 */
export function startProblem(args: {
  captainIds: readonly string[];
  accepted: ReadonlySet<string>;
  poolSize: number;
}): string | null {
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
  picks: readonly Pick[];
  names: Readonly<Record<string, string>>;
  teamNames?: Readonly<Record<string, string>>;
}): DraftTeam[] {
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
