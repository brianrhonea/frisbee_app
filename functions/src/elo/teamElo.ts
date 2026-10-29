/**
 * Team-level Elo for USA Ultimate divisions.
 *
 * Every team starts at `base`. Games are replayed in date order; each game
 * moves the two teams by equal and opposite amounts:
 *
 *   expected = 1 / (1 + 10^((rB - rA) / scale))
 *   delta    = k * mov(margin) * (result - expected)
 *
 * `mov` grows with the log of the winning margin and is 1 at `movNorm`
 * points, so a 15-5 rout counts for more than a 15-13 squeaker without
 * letting blowouts dominate. Games involving a team in its first
 * `provisionalGames` games use a larger K so new entries settle quickly.
 * Ultimate is played at neutral sites, so there is no home-field term.
 */

export interface EloConfig {
  base: number;
  k: number;
  scale: number;
  movNorm: number;
  provisionalGames: number;
  /** Extra K multiplier for a team's first game, tapering to 1. */
  provisionalBoost: number;
}

export const DEFAULT_ELO: EloConfig = {
  base: 1500,
  k: 40,
  scale: 400,
  movNorm: 7,
  provisionalGames: 5,
  provisionalBoost: 2,
};

export interface EloGame {
  /** "YYYY-MM-DD"; games are replayed in this order. */
  playedOn: string;
  a: string;
  b: string;
  scoreA: number;
  scoreB: number;
}

export interface TeamRating {
  team: string;
  elo: number;
  games: number;
  wins: number;
  losses: number;
}

export const expectedScore = (ra: number, rb: number, scale = DEFAULT_ELO.scale) =>
  1 / (1 + Math.pow(10, (rb - ra) / scale));

export function movMultiplier(margin: number, movNorm = DEFAULT_ELO.movNorm): number {
  return margin <= 0 ? 1 : Math.log1p(margin) / Math.log1p(movNorm);
}

/** Replays `games` and returns every team's rating, highest first. */
export function rateTeams(games: EloGame[], cfg: EloConfig = DEFAULT_ELO): TeamRating[] {
  const teams = new Map<string, TeamRating>();
  const get = (team: string) => {
    let t = teams.get(team);
    if (!t) teams.set(team, (t = { team, elo: cfg.base, games: 0, wins: 0, losses: 0 }));
    return t;
  };
  const kFor = (t: TeamRating) => {
    if (t.games >= cfg.provisionalGames) return cfg.k;
    const left = 1 - t.games / cfg.provisionalGames;
    return cfg.k * (1 + (cfg.provisionalBoost - 1) * left);
  };

  const ordered = [...games].sort((x, y) => x.playedOn.localeCompare(y.playedOn));
  for (const g of ordered) {
    if (g.a === g.b) continue;
    const a = get(g.a);
    const b = get(g.b);
    const result = g.scoreA > g.scoreB ? 1 : g.scoreA < g.scoreB ? 0 : 0.5;
    const residual = result - expectedScore(a.elo, b.elo, cfg.scale);
    const mov = movMultiplier(Math.abs(g.scoreA - g.scoreB), cfg.movNorm);
    // One shared K keeps every game zero-sum, so a division's mean stays at
    // `base`; a newcomer on either side speeds up both changes.
    const delta = ((kFor(a) + kFor(b)) / 2) * mov * residual;
    a.elo += delta;
    b.elo -= delta;
    a.games++;
    b.games++;
    if (result === 1) {
      a.wins++;
      b.losses++;
    } else if (result === 0) {
      b.wins++;
      a.losses++;
    }
  }
  return [...teams.values()].sort((x, y) => y.elo - x.elo);
}
