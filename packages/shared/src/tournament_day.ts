import { type EngineGame, gamesToPlay, poolTeams, type SlotSource, standings, winnerOf } from "./tournament_engine.js";

/** When a team's tournament card shows (TournamentDayPhase in the app). */
export type TournamentDayPhase = "today" | "tomorrow";

/** What a score needs from the team's captains (ScoreDueKind in the app). */
export type ScoreDueKind = "report" | "confirm" | "awaiting";

/** A team's game from its side (TeamGame in the app). */
export interface TeamGame {
  game: EngineGame;
  /** The other team; null while its slot isn't filled. */
  opponent: string | null;
  scoreFor: number | null;
  scoreAgainst: number | null;
  won: boolean;
}

/** A team's day at a tournament (TournamentDay in the app). */
export interface TournamentDay {
  phase: TournamentDayPhase;
  next: TeamGame | null;
  last: TeamGame | null;
  wins: number;
  losses: number;
  pool: string | null;
  /** 1 = top; null until the team has a pool result (before that it's only the seed). */
  poolPlace: number | null;
  poolSize: number | null;
  scoreDue: EngineGame | null;
  scoreDueKind: ScoreDueKind | null;
  /**
   * With no `next` game yet, whether an empty bracket slot comes from this
   * team (its pool rank, or the winner or loser of a game it played): its
   * next game is still to be decided. False once it's out.
   */
  awaiting: boolean;
}

const isDone = (g: EngineGame) => g.status === "done";
const dayKey = (d: Date) => d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();

function teamGame(game: EngineGame, teamId: string): TeamGame {
  const a = game.teamA === teamId;
  return {
    game,
    opponent: a ? game.teamB : game.teamA,
    scoreFor: a ? game.scoreA : game.scoreB,
    scoreAgainst: a ? game.scoreB : game.scoreA,
    won: isDone(game) && winnerOf(game) === teamId,
  };
}

/**
 * The card for [teamId] on [games] at [now], or null when there's nothing
 * to show: no game today, not [live], and not the evening (17:00 on)
 * before a game tomorrow. Checked on fixtures/tournament_day/day.json,
 * which the app writes.
 */
export function tournamentDay(games: EngineGame[], teamId: string, now: Date, live = false): TournamentDay | null {
  const mine = (g: EngineGame) => g.teamA === teamId || g.teamB === teamId;
  const byTime = (a: EngineGame, b: EngineGame) => {
    const x = a.startsAt?.getTime();
    const y = b.startsAt?.getTime();
    if (x != null && y != null && x !== y) return x - y;
    if ((x == null) !== (y == null)) return x == null ? 1 : -1;
    return a.order - b.order;
  };
  const toPlay = gamesToPlay(games).filter(mine).sort(byTime);
  const done = games.filter((g) => isDone(g) && mine(g)).sort(byTime);
  const next = toPlay[0] ?? null;
  const last = done[done.length - 1] ?? null;

  const today = dayKey(now);
  const tomorrow = dayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1));
  const dayOf = (g: EngineGame | null) => (g?.startsAt ? dayKey(g.startsAt) : null);
  const playsToday = dayOf(next) === today || done.some((g) => dayOf(g) === today) || toPlay.some((g) => dayOf(g) === today);
  let phase: TournamentDayPhase;
  if (playsToday || (live && next)) phase = "today";
  else if (dayOf(next) === tomorrow && now.getHours() >= 17) phase = "tomorrow";
  else return null;

  const wins = done.filter((g) => winnerOf(g) === teamId).length;

  let pool: string | null = null;
  let poolPlace: number | null = null;
  let poolRank: number | null = null;
  let poolSize: number | null = null;
  for (const [id, teams] of poolTeams(games)) {
    if (!teams.includes(teamId)) continue;
    const rows = standings(
      teams,
      games.filter((g) => g.stage === "pool" && g.pool === id),
    );
    pool = id;
    poolSize = rows.length;
    poolRank = rows.findIndex((s) => s.teamId === teamId) + 1;
    if (done.some((g) => g.stage === "pool" && g.pool === id)) poolPlace = poolRank;
    break;
  }

  let scoreDue: EngineGame | null = null;
  let scoreDueKind: ScoreDueKind | null = null;
  for (const g of toPlay) {
    if (g.teamA == null || g.teamB == null) continue;
    if (g.status === "reported" && g.report) {
      scoreDue = g;
      scoreDueKind = g.report.byTeam === teamId ? "awaiting" : "confirm";
      break;
    }
    if (!g.startsAt || g.startsAt.getTime() <= now.getTime()) {
      scoreDue = g;
      scoreDueKind = "report";
      break;
    }
  }

  const fromMe = (s: SlotSource | null | undefined): boolean => {
    if (!s) return false;
    if (s.type === "pool") return s.pool === pool && s.rank === poolRank;
    const g = done.find((x) => x.id === s.game);
    if (!g) return false;
    return s.type === "winner" ? winnerOf(g) === teamId : winnerOf(g) !== teamId;
  };
  const awaiting =
    next == null && gamesToPlay(games).some((g) => (g.teamA == null && fromMe(g.sourceA)) || (g.teamB == null && fromMe(g.sourceB)));

  return {
    phase,
    next: next && teamGame(next, teamId),
    last: last && teamGame(last, teamId),
    wins,
    losses: done.length - wins,
    pool,
    poolPlace,
    poolSize,
    scoreDue,
    scoreDueKind,
    awaiting,
  };
}
