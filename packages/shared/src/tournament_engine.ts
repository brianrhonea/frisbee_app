// The tournament engine, ported from the app (apps/mobile/lib/domain/
// tournament_engine: generator.dart, season.dart, standings.dart and
// progress.dart): schedules for pools, brackets and league seasons,
// standings, and how results move teams on. Pure and shared, so the
// website builds the same schedule the app does and the API checks score
// changes the same way.
//
// Dates are Date objects. Calendar maths (a league's weekly nights) is in
// the runtime's local time zone, as the app does on the phone: run it in
// the browser, not on the server. Group tournaments (group_tournaments.ts)
// use the same engine with ISO-string dates: everything but scheduling
// works on any game shape (GameLike), and groupEngine adapts scheduleFor.

export const tournamentFormats = ["roundRobin", "poolsSingleElim", "singleElim", "doubleElim", "poolsPlacement"] as const;
export type TournamentFormat = (typeof tournamentFormats)[number];

export const tournamentFormatLabels: Record<TournamentFormat, { label: string; summary: string }> = {
  roundRobin: { label: "Round robin", summary: "Everyone plays everyone; best record wins" },
  poolsSingleElim: { label: "Pool play + single elimination", summary: "Pools first, then a bracket seeded by pool finish" },
  singleElim: { label: "Single elimination", summary: "Lose once and you are out" },
  doubleElim: { label: "Double elimination", summary: "Lose twice and you are out" },
  poolsPlacement: { label: "Pool play + placement bracket", summary: "Pools, then brackets where every team plays for a final place" },
};

export const scoringModes = ["points", "time"] as const;
export type ScoringMode = (typeof scoringModes)[number];

export const gameStages = ["pool", "winners", "losers", "grandFinal", "reset", "crossover", "placement"] as const;
export type GameStage = (typeof gameStages)[number];
export const isBracketStage = (s: GameStage) => s !== "pool";

export const gameStatuses = ["scheduled", "reported", "done"] as const;
export type GameStatus = (typeof gameStatuses)[number];

/** Where a game's team comes from before it's known (SlotSource.toMap). */
export type SlotSource =
  | { type: "winner"; game: string }
  | { type: "loser"; game: string }
  | { type: "pool"; pool: string; rank: number };

export interface ScoreReport {
  scoreA: number;
  scoreB: number;
  /** The team whose captain reported it. */
  byTeam: string;
}

/** One game (GroupGame), keyed as stored; [D] is how its start is held. */
export interface EngineGameOf<D> {
  id: string;
  order: number;
  stage: GameStage;
  round: number;
  label: string;
  pool: string | null;
  field: number;
  startsAt: D | null;
  teamA: string | null;
  teamB: string | null;
  sourceA: SlotSource | null;
  sourceB: SlotSource | null;
  status: GameStatus;
  scoreA: number | null;
  scoreB: number | null;
  report: ScoreReport | null;
  ifNeeded: boolean;
  /** Placement games only: the winner's place. */
  place?: number | null;
}

/** A game with Date starts (hosted tournaments and leagues). */
export type EngineGame = EngineGameOf<Date>;

/** Any game, whatever its dates are: what the engine reads. */
export type GameLike = EngineGameOf<unknown>;

/** What a division's games follow (TournamentSettings). */
export interface EngineSettings {
  format: TournamentFormat;
  playersOnField: number;
  poolCount: number;
  gameMinutes: number;
  breakMinutes: number;
  scoreCap: number;
  timeoutsPerHalf: number;
  fields: number;
  startsAt: Date;
  idealEndsAt: Date | null;
  laterDays: Date[];
  scoring: ScoringMode;
}

/** A league's season (LeagueSeason). */
export interface EngineSeason {
  weeks: number;
  playoffWeeks: number;
  playoffTeams: number;
  gamesPerNight: number;
  skipDates: Date[];
}

export const seasonHasPlayoffs = (s: EngineSeason) => s.playoffTeams > 0 && s.playoffWeeks > 0;
export const regularWeeks = (s: EngineSeason) => (seasonHasPlayoffs(s) ? s.weeks - s.playoffWeeks : s.weeks);

export const isDone = (g: GameLike) => g.status === "done";
export const hasTeams = (g: GameLike) => g.teamA != null && g.teamB != null;
export const winnerOf = (g: GameLike): string | null =>
  !isDone(g) ? null : (g.scoreA ?? 0) > (g.scoreB ?? 0) ? g.teamA : g.teamB;
export const loserOf = (g: GameLike): string | null =>
  !isDone(g) ? null : (g.scoreA ?? 0) > (g.scoreB ?? 0) ? g.teamB : g.teamA;

export class ScheduleError extends Error {}

export interface ScheduleDay {
  startsAt: Date;
  /** When the day's last game should finish. */
  endsAt: Date;
  games: number;
}

export interface SchedulePlan {
  games: EngineGame[];
  days: ScheduleDay[];
}

const minutes = (n: number) => n * 60_000;
const at = (d: Date, ms: number) => new Date(d.getTime() + ms);

// ---- Standings (standings.dart) ---------------------------------------------

export interface Standing {
  teamId: string;
  wins: number;
  losses: number;
  pointsFor: number;
  pointsAgainst: number;
}
export const pointDiff = (s: Standing) => s.pointsFor - s.pointsAgainst;

/** Pool ids in order: "A", "B", ... */
export const poolName = (index: number) => String.fromCharCode(65 + index);

/** Teams of each pool, from its games, pools in name order. */
export function poolTeams(games: GameLike[]): Map<string, string[]> {
  const pools = new Map<string, Set<string>>();
  for (const g of games) {
    if (g.stage !== "pool" || g.pool == null) continue;
    const set = pools.get(g.pool) ?? new Set<string>();
    if (g.teamA != null) set.add(g.teamA);
    if (g.teamB != null) set.add(g.teamB);
    pools.set(g.pool, set);
  }
  return new Map([...pools.keys()].sort().map((k) => [k, [...(pools.get(k) ?? [])]]));
}

export const poolComplete = (poolId: string, games: GameLike[]) =>
  games.filter((g) => g.stage === "pool" && g.pool === poolId).every(isDone);

/**
 * [teamIds] ranked by results: most wins, then head to head among the tied
 * teams, then point differential, then points scored; remaining ties keep
 * [teamIds] order.
 */
export function standings(teamIds: string[], games: Iterable<GameLike>): Standing[] {
  const ids = new Set(teamIds);
  const done = [...games].filter((g) => isDone(g) && g.teamA != null && g.teamB != null && ids.has(g.teamA) && ids.has(g.teamB));
  const rows = new Map(teamIds.map((id) => [id, { teamId: id, wins: 0, losses: 0, pointsFor: 0, pointsAgainst: 0 } as Standing]));
  for (const g of done) {
    const a = rows.get(g.teamA as string) as Standing;
    const b = rows.get(g.teamB as string) as Standing;
    a.pointsFor += g.scoreA ?? 0;
    a.pointsAgainst += g.scoreB ?? 0;
    b.pointsFor += g.scoreB ?? 0;
    b.pointsAgainst += g.scoreA ?? 0;
    if (winnerOf(g) === a.teamId) {
      a.wins++;
      b.losses++;
    } else {
      b.wins++;
      a.losses++;
    }
  }
  const headToHead = (s: Standing, tied: Set<string>) =>
    done.filter((g) => winnerOf(g) === s.teamId && tied.has(g.teamA as string) && tied.has(g.teamB as string)).length;
  const byWins = new Map<number, Standing[]>();
  for (const r of rows.values()) byWins.set(r.wins, [...(byWins.get(r.wins) ?? []), r]);
  return [...byWins.keys()]
    .sort((a, b) => b - a)
    .flatMap((w) => {
      const group = byWins.get(w) as Standing[];
      const tied = new Set(group.map((s) => s.teamId));
      return group.sort((x, y) => {
        const h2h = headToHead(y, tied) - headToHead(x, tied);
        if (h2h !== 0) return h2h;
        const diff = pointDiff(y) - pointDiff(x);
        if (diff !== 0) return diff;
        const pf = y.pointsFor - x.pointsFor;
        if (pf !== 0) return pf;
        return teamIds.indexOf(x.teamId) - teamIds.indexOf(y.teamId);
      });
    });
}

// ---- Generator (generator.dart) ---------------------------------------------

type Entrant = { team: string; source: null } | { team: null; source: SlotSource };
const team = (t: string): Entrant => ({ team: t, source: null });
const source = (s: SlotSource): Entrant => ({ team: null, source: s });

interface Match {
  winner: Entrant | null;
  loser: Entrant | null;
  gameId: string | null;
}

class Builder {
  games: EngineGame[] = [];

  private nextId() {
    return `g${String(this.games.length + 1).padStart(3, "0")}`;
  }

  match(a: {
    stage: GameStage;
    round: number;
    label: string;
    a: Entrant | null;
    c: Entrant | null;
    place?: number | null;
  }): Match {
    if (a.a == null || a.c == null) return { winner: a.a ?? a.c, loser: null, gameId: null };
    const id = this.add({ ...a, a: a.a, c: a.c });
    return { winner: source({ type: "winner", game: id }), loser: source({ type: "loser", game: id }), gameId: id };
  }

  add(a: {
    stage: GameStage;
    round: number;
    label: string;
    a: Entrant;
    c: Entrant;
    pool?: string | null;
    ifNeeded?: boolean;
    place?: number | null;
  }): string {
    const id = this.nextId();
    this.games.push({
      id,
      order: this.games.length,
      stage: a.stage,
      round: a.round,
      label: a.label,
      pool: a.pool ?? null,
      field: 1,
      startsAt: null,
      teamA: a.a.team,
      teamB: a.c.team,
      sourceA: a.a.source,
      sourceB: a.c.source,
      status: "scheduled",
      scoreA: null,
      scoreB: null,
      report: null,
      ifNeeded: a.ifNeeded ?? false,
      ...(a.place != null && { place: a.place }),
    });
    return id;
  }
}

/** Every pairing of [teams], by round (circle method); odd counts sit one out. */
export function roundRobin<T>(teams: T[]): Array<Array<[T, T]>> {
  const list: Array<T | null> = [...teams, ...(teams.length % 2 === 1 ? [null] : [])];
  const n = list.length;
  if (n < 2) return [];
  const rounds: Array<Array<[T, T]>> = [];
  for (let r = 0; r < n - 1; r++) {
    const round: Array<[T, T]> = [];
    for (let i = 0; i < Math.floor(n / 2); i++) {
      const a = list[i];
      const c = list[n - 1 - i];
      if (a != null && c != null) round.push([a, c]);
    }
    rounds.push(round);
    list.splice(1, 0, list.pop() as T | null);
  }
  return rounds;
}

function pools(b: Builder, teams: string[], count: number): Map<string, string[]> {
  const ids = Array.from({ length: count }, (_, i) => poolName(i));
  const map = new Map(ids.map((p) => [p, [] as string[]]));
  for (let i = 0; i < teams.length; i++) {
    const lap = Math.floor(i / count);
    const at = i % count;
    map.get(ids[lap % 2 === 0 ? at : count - 1 - at])?.push(teams[i]);
  }
  const rounds = new Map(ids.map((p) => [p, roundRobin(map.get(p) ?? [])]));
  const most = Math.max(0, ...[...rounds.values()].map((r) => r.length));
  for (let r = 0; r < most; r++) {
    for (const p of ids) {
      const pr = rounds.get(p) ?? [];
      if (r >= pr.length) continue;
      for (const [a, c] of pr[r]) {
        b.add({
          stage: "pool",
          round: r + 1,
          label: count === 1 ? `Round ${r + 1}` : `Pool ${p} · Round ${r + 1}`,
          pool: p,
          a: team(a),
          c: team(c),
        });
      }
    }
  }
  return map;
}

function crossSeed(map: Map<string, string[]>): Entrant[] {
  const ids = [...map.keys()];
  const deepest = Math.max(0, ...[...map.values()].map((p) => p.length));
  const out: Entrant[] = [];
  for (let rank = 1; rank <= deepest; rank++) {
    for (const p of rank % 2 === 1 ? ids : [...ids].reverse()) {
      if ((map.get(p)?.length ?? 0) >= rank) out.push(source({ type: "pool", pool: p, rank }));
    }
  }
  return out;
}

/** Bracket positions for [size] seeds (a power of two), in match order. */
export function seedOrder(size: number): number[] {
  let order = [1];
  while (order.length < size) {
    const n = order.length * 2;
    order = order.flatMap((s) => [s, n + 1 - s]);
  }
  return order;
}

function bracketSize(n: number) {
  let p = 1;
  while (p < n) p *= 2;
  return p;
}

function roundName(matches: number, round: number) {
  return matches === 1 ? "Final" : matches === 2 ? "Semifinal" : matches === 4 ? "Quarterfinal" : `Round ${round}`;
}

function firstRound(entrants: Entrant[]): Array<Entrant | null> {
  return seedOrder(bracketSize(entrants.length)).map((seed) => (seed <= entrants.length ? entrants[seed - 1] : null));
}

function singleElim(b: Builder, entrants: Entrant[]) {
  let current = firstRound(entrants);
  let round = 1;
  while (current.length > 1) {
    const matches = current.length / 2;
    const next: Array<Entrant | null> = [];
    for (let i = 0; i < matches; i++) {
      next.push(b.match({ stage: "winners", round, label: roundName(matches, round), a: current[2 * i], c: current[2 * i + 1] }).winner);
    }
    current = next;
    round++;
  }
}

/** Suggested pool count for [teams] teams. */
export const suggestedPools = (teams: number) => (teams <= 6 ? 1 : Math.max(2, Math.round(teams / 4.5)));

/** A round robin for small fields, otherwise pools and a placement bracket. */
export const suggestedFormat = (teams: number): TournamentFormat => (teams <= 5 ? "roundRobin" : "poolsPlacement");

export function ordinal(n: number) {
  const teen = n % 100 >= 11 && n % 100 <= 13;
  const suffix = teen ? "th" : n % 10 === 1 ? "st" : n % 10 === 2 ? "nd" : n % 10 === 3 ? "rd" : "th";
  return `${n}${suffix}`;
}

function placement(b: Builder, entrants: Entrant[]) {
  const crossover = entrants.length < bracketSize(entrants.length);
  let level: Array<[Array<Entrant | null>, number]> = [[firstRound(entrants), 1]];
  let round = 1;
  while (level.length > 0) {
    const next: Array<[Array<Entrant | null>, number]> = [];
    for (const [slots, place] of level) {
      if (slots.length < 2) continue;
      const matches = slots.length / 2;
      const name = roundName(matches, round);
      const label =
        place === 1
          ? round === 1 && crossover
            ? "Crossover"
            : name
          : matches === 1
            ? `${ordinal(place)} place`
            : `${ordinal(place)}–${ordinal(place + slots.length - 1)} ${name.toLowerCase()}`;
      const stage: GameStage = round === 1 && crossover ? "crossover" : place === 1 ? "winners" : "placement";
      const results: Match[] = [];
      for (let i = 0; i < matches; i++) {
        results.push(b.match({ stage, round, label, a: slots[2 * i], c: slots[2 * i + 1], place: matches === 1 ? place : null }));
      }
      if (matches === 1) continue;
      next.push([results.map((r) => r.winner), place]);
      next.push([results.map((r) => r.loser), place + matches]);
    }
    level = next;
    round++;
  }
}

function doubleElim(b: Builder, entrants: Entrant[]) {
  let winners = firstRound(entrants);
  const droppedByRound: Array<Array<Entrant | null>> = [];
  let round = 1;
  while (winners.length > 1) {
    const matches = winners.length / 2;
    const results: Match[] = [];
    for (let i = 0; i < matches; i++) {
      results.push(
        b.match({ stage: "winners", round, label: `Winners' ${roundName(matches, round).toLowerCase()}`, a: winners[2 * i], c: winners[2 * i + 1] }),
      );
    }
    winners = results.map((r) => r.winner);
    droppedByRound.push(results.map((r) => r.loser));
    round++;
  }
  const wbChampion = winners[0];

  let lbRound = 0;
  const lbMatches = (sideA: Array<Entrant | null>, sideB: Array<Entrant | null>) => {
    lbRound++;
    return sideA.map((a, i) => b.match({ stage: "losers", round: lbRound, label: `Losers' round ${lbRound}`, a, c: sideB[i] }).winner);
  };
  const evens = (l: Array<Entrant | null>) => l.filter((_, i) => i % 2 === 0);
  const odds = (l: Array<Entrant | null>) => l.filter((_, i) => i % 2 === 1);
  let losers = droppedByRound[0] ?? [];
  if (losers.length > 1) losers = lbMatches(evens(losers), odds(losers));
  for (let r = 1; r < droppedByRound.length; r++) {
    const drop = droppedByRound[r];
    losers = lbMatches(losers, r % 2 === 1 ? [...drop].reverse() : drop);
    if (losers.length > 1) losers = lbMatches(evens(losers), odds(losers));
  }
  const lbChampion = losers[0] ?? null;

  const finalRound = droppedByRound.length + 1;
  const grand = b.match({ stage: "grandFinal", round: finalRound, label: "Final", a: wbChampion, c: lbChampion });
  if (grand.gameId == null) return;
  b.add({
    stage: "reset",
    round: finalRound + 1,
    label: "Final (if needed)",
    a: source({ type: "loser", game: grand.gameId }),
    c: source({ type: "winner", game: grand.gameId }),
    ifNeeded: true,
  });
}

function dependencies(games: GameLike[]): Map<string, Set<string>> {
  const byPool = new Map<string, Set<string>>();
  for (const g of games) {
    if (g.stage === "pool") byPool.set(g.pool ?? "", (byPool.get(g.pool ?? "") ?? new Set()).add(g.id));
  }
  const from = (s: SlotSource | null): Set<string> =>
    s == null ? new Set() : s.type === "pool" ? (byPool.get(s.pool) ?? new Set()) : new Set([s.game]);
  return new Map(games.map((g) => [g.id, new Set([...from(g.sourceA), ...from(g.sourceB)])]));
}

/** How many of [total] games each of [days] days gets. */
export function gamesPerDay(total: number, days: number): number[] {
  return Array.from({ length: days }, (_, d) => Math.floor(total / days) + (d < total % days ? 1 : 0));
}

const teamsOf = (g: GameLike) => [g.teamA, g.teamB].filter((t): t is string => t != null);

function schedule(games: EngineGame[], s: EngineSettings): SchedulePlan {
  const fields = Math.max(1, s.fields);
  const slotLength = minutes(s.gameMinutes + s.breakMinutes);
  const deps = dependencies(games);
  const starts = [s.startsAt, ...s.laterDays];
  const quotas = gamesPerDay(games.length, starts.length);
  const scheduled: EngineGame[] = [];
  const days: ScheduleDay[] = [];
  const earlier = new Set<string>();
  let next = 0;
  for (let d = 0; d < starts.length; d++) {
    const pending = games.slice(next, next + quotas[d]);
    next += quotas[d];
    const slotOf = new Map<string, number>();
    let slot = 0;
    let last = -1;
    while (pending.length > 0) {
      const busy = new Set<string>();
      let used = 0;
      for (const g of [...pending]) {
        if (used === fields) break;
        const ready = [...(deps.get(g.id) ?? [])].every((dep) => earlier.has(dep) || (slotOf.get(dep) ?? slot) < slot);
        const teams = teamsOf(g);
        if (!ready || teams.some((t) => busy.has(t))) continue;
        for (const t of teams) busy.add(t);
        slotOf.set(g.id, slot);
        pending.splice(pending.indexOf(g), 1);
        used++;
        last = slot;
        scheduled.push({ ...g, order: scheduled.length, field: used, startsAt: at(starts[d], slotLength * slot) });
      }
      slot++;
      if (slot > games.length * 2 + 2) throw new ScheduleError("These games can't be scheduled.");
    }
    for (const k of slotOf.keys()) earlier.add(k);
    days.push({
      startsAt: starts[d],
      endsAt: last < 0 ? starts[d] : at(starts[d], slotLength * last + minutes(s.gameMinutes)),
      games: quotas[d],
    });
  }
  return { games: scheduled, days };
}

/** Every game for [teams] (seed order) under [s], scheduled. */
export function scheduleFor(teams: string[], s: EngineSettings): SchedulePlan {
  if (teams.length < 2) throw new ScheduleError("A tournament needs at least two teams.");
  const b = new Builder();
  const clampPools = (n: number) => Math.min(Math.max(n, 1), Math.floor(teams.length / 2));
  switch (s.format) {
    case "roundRobin":
      pools(b, teams, 1);
      break;
    case "poolsSingleElim":
      singleElim(b, crossSeed(pools(b, teams, clampPools(s.poolCount))));
      break;
    case "singleElim":
      singleElim(b, teams.map(team));
      break;
    case "doubleElim":
      doubleElim(b, teams.map(team));
      break;
    case "poolsPlacement": {
      const count = clampPools(s.poolCount);
      placement(b, count === 1 ? teams.map(team) : crossSeed(pools(b, teams, count)));
      break;
    }
  }
  return schedule(b.games, s);
}

// ---- Season (season.dart) ----------------------------------------------------

const dayKey = (d: Date) => d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();

/** Each night of the season: the first and every seven days on, minus skipped dates. */
export function seasonNights(s: EngineSettings, season: EngineSeason): Date[] {
  const skip = new Set(season.skipDates.map(dayKey));
  const first = s.startsAt;
  const nights: Date[] = [];
  for (let week = 0; nights.length < season.weeks; week++) {
    // From the calendar date, so a clock change doesn't shift the hour.
    const night = new Date(first.getFullYear(), first.getMonth(), first.getDate() + 7 * week, first.getHours(), first.getMinutes());
    if (!skip.has(dayKey(night))) nights.push(night);
    if (week > 1000) break;
  }
  return nights;
}

/** A league's season for [teams]: a weekly round robin, then playoffs. */
export function seasonFor(teams: string[], s: EngineSettings, season: EngineSeason): SchedulePlan {
  if (teams.length < 2) throw new ScheduleError("A league needs at least two teams.");
  const regular = regularWeeks(season);
  if (regular < 1) throw new ScheduleError("Leave at least one week for the regular season.");
  const nights = seasonNights(s, season);
  const b = new Builder();
  const nightOf = new Map<string, number>();
  const rounds = roundRobin(teams);
  let next = 0;
  for (let w = 0; w < regular; w++) {
    for (let g = 0; g < season.gamesPerNight; g++) {
      for (const [a, c] of rounds[next % rounds.length]) {
        const id = b.add({ stage: "pool", round: w + 1, label: `Week ${w + 1}`, pool: "A", a: team(a), c: team(c) });
        nightOf.set(id, w);
      }
      next++;
    }
  }
  if (seasonHasPlayoffs(season)) {
    const size = Math.min(season.playoffTeams, teams.length);
    const before = b.games.length;
    singleElim(
      b,
      Array.from({ length: size }, (_, i) => source({ type: "pool", pool: "A", rank: i + 1 })),
    );
    const bracket = b.games.slice(before);
    const bracketRounds = Math.max(0, ...bracket.map((g) => g.round));
    const weeks = season.playoffWeeks;
    for (const g of bracket) {
      const night = weeks >= bracketRounds ? weeks - bracketRounds + g.round - 1 : Math.floor(((g.round - 1) * weeks) / bracketRounds);
      nightOf.set(g.id, regular + night);
    }
  }

  const fields = Math.max(1, s.fields);
  const slotLength = minutes(s.gameMinutes + s.breakMinutes);
  const scheduled: EngineGame[] = [];
  const days: ScheduleDay[] = [];
  const earlier = new Set<string>();
  for (let n = 0; n < nights.length; n++) {
    const pending = b.games.filter((g) => nightOf.get(g.id) === n);
    if (pending.length === 0) continue;
    const slotOf = new Map<string, number>();
    let slot = 0;
    let last = -1;
    while (pending.length > 0) {
      const busy = new Set<string>();
      let used = 0;
      for (const g of [...pending]) {
        if (used === fields) break;
        const ready = [g.sourceA, g.sourceB].every(
          (src) => src == null || src.type === "pool" || earlier.has(src.game) || (slotOf.get(src.game) ?? slot) < slot,
        );
        const playing = teamsOf(g);
        if (!ready || playing.some((t) => busy.has(t))) continue;
        for (const t of playing) busy.add(t);
        slotOf.set(g.id, slot);
        pending.splice(pending.indexOf(g), 1);
        used++;
        last = slot;
        scheduled.push({ ...g, order: scheduled.length, field: used, startsAt: at(nights[n], slotLength * slot) });
      }
      slot++;
      if (slot > b.games.length * 2 + 2) throw new ScheduleError("These games can't be scheduled.");
    }
    for (const k of slotOf.keys()) earlier.add(k);
    days.push({ startsAt: nights[n], endsAt: at(nights[n], slotLength * last + minutes(s.gameMinutes)), games: slotOf.size });
  }
  return { games: scheduled, days };
}

/** Teams with no pool game in [week]: the bye. */
export function byesIn(teams: string[], games: Iterable<GameLike>, week: number): string[] {
  const playing = new Set<string>();
  for (const g of games) if (g.stage === "pool" && g.round === week) for (const t of teamsOf(g)) playing.add(t);
  return teams.filter((t) => !playing.has(t));
}

// ---- Progress (progress.dart) -----------------------------------------------

/** A team to write into a waiting game once it's known. */
export interface SlotFill {
  gameId: string;
  teamA: string | null;
  teamB: string | null;
}

/** Teams that move on once [finished] is final. */
export function fillsAfter(finished: GameLike, games: GameLike[], overwrite = false): SlotFill[] {
  const winner = winnerOf(finished);
  const loser = loserOf(finished);
  if (winner == null || loser == null) return [];
  const resolve = (s: SlotSource | null) =>
    s?.type === "winner" && s.game === finished.id ? winner : s?.type === "loser" && s.game === finished.id ? loser : null;
  const fill = (current: string | null, s: SlotSource | null) => {
    const t = resolve(s);
    if (t == null || t === current) return null;
    return current == null || overwrite ? t : null;
  };
  const out: SlotFill[] = [];
  for (const g of games) {
    if (g.id === finished.id || isDone(g)) continue;
    const a = fill(g.teamA, g.sourceA);
    const b = fill(g.teamB, g.sourceB);
    if (a == null && b == null) continue;
    if (g.stage === "reset" && finished.stage === "grandFinal" && winner !== finished.teamB) continue;
    out.push({ gameId: g.id, teamA: a, teamB: b });
  }
  return out;
}

/** Whether a game fed by [game]'s result has been played or reported. */
export const laterGamesPlayed = (game: GameLike, games: GameLike[]) =>
  games.some(
    (g) => g.status !== "scheduled" && [g.sourceA, g.sourceB].some((s) => s != null && s.type !== "pool" && s.game === game.id),
  );

/** Fills that should already have been written for finished games. */
export const pendingFills = (games: GameLike[]) => games.filter(isDone).flatMap((g) => fillsAfter(g, games));

/** Seeds bracket games from pool standings once every pool is complete. */
export function bracketSeeds(games: GameLike[]): SlotFill[] {
  const map = poolTeams(games);
  if (map.size === 0 || ![...map.keys()].every((p) => poolComplete(p, games))) return [];
  const ranked = new Map(
    [...map.entries()].map(([p, ids]) => [p, standings(ids, games.filter((g) => g.pool === p)).map((s) => s.teamId)]),
  );
  const resolve = (s: SlotSource | null) => (s?.type === "pool" ? (ranked.get(s.pool)?.[s.rank - 1] ?? null) : null);
  const out: SlotFill[] = [];
  for (const g of games) {
    const a = g.teamA == null ? resolve(g.sourceA) : null;
    const b = g.teamB == null ? resolve(g.sourceB) : null;
    if (a != null || b != null) out.push({ gameId: g.id, teamA: a, teamB: b });
  }
  return out;
}

export const awaitingSeeds = (games: GameLike[]) =>
  games.some((g) => (g.teamA == null && g.sourceA?.type === "pool") || (g.teamB == null && g.sourceB?.type === "pool"));

/** Games still to be played; the if-needed final drops out once it isn't needed. */
export function gamesToPlay<G extends GameLike>(games: G[]): G[] {
  const grand = games.find((g) => g.stage === "grandFinal");
  const resetNeeded = grand == null || !isDone(grand) ? true : winnerOf(grand) === grand.teamB;
  return games.filter((g) => !isDone(g) && !(g.ifNeeded && !resetNeeded));
}

export const skippedGame = (game: GameLike, games: GameLike[]) =>
  game.ifNeeded && !isDone(game) && !gamesToPlay(games).some((g) => g.id === game.id);

/** The winner once every game that needs playing is done. */
export function championOf(format: TournamentFormat, games: GameLike[]): string | null {
  if (games.length === 0 || gamesToPlay(games).length > 0) return null;
  if (format === "roundRobin") {
    const pool = [...poolTeams(games).values()][0] ?? [];
    return standings(pool, games)[0]?.teamId ?? null;
  }
  const finalGame = games.find((g) => g.place === 1);
  if (finalGame) return winnerOf(finalGame);
  const reset = games.find((g) => g.stage === "reset");
  if (reset && isDone(reset)) return winnerOf(reset);
  const grand = games.find((g) => g.stage === "grandFinal");
  if (grand) return winnerOf(grand);
  const fed = new Set<string>();
  for (const g of games) for (const s of [g.sourceA, g.sourceB]) if (s?.type === "winner") fed.add(s.game);
  const last = games.filter((g) => isBracketStage(g.stage) && !fed.has(g.id)).pop();
  return last ? winnerOf(last) : null;
}

/** Final places, best first, once every game is played; empty until then. */
export function placementsOf(format: TournamentFormat, seeds: string[], games: GameLike[]): string[] {
  if (games.length === 0 || gamesToPlay(games).length > 0) return [];
  const byPlace = new Map<number, string>();
  for (const g of games) {
    if (g.place == null || !isDone(g)) continue;
    byPlace.set(g.place, winnerOf(g) as string);
    byPlace.set(g.place + 1, loserOf(g) as string);
  }
  const placed = [...byPlace.keys()].sort((a, b) => a - b).map((p) => byPlace.get(p) as string);
  if (placed.length === 0) {
    if (format === "roundRobin") {
      const pool = [...poolTeams(games).values()][0] ?? [];
      placed.push(...standings(pool, games).map((s) => s.teamId));
    } else {
      const champ = championOf(format, games);
      if (champ != null) placed.push(champ);
    }
  }
  return [...placed, ...seeds.filter((t) => !placed.includes(t))];
}

/** Valid scores: whole numbers, no ties. */
export function scoreError(a: number | null | undefined, b: number | null | undefined, max = 99): string | null {
  if (a == null || b == null || !Number.isInteger(a) || !Number.isInteger(b)) return "Enter both scores.";
  if (a < 0 || b < 0 || a > max || b > max) return `Scores go from 0 to ${max}.`;
  if (a === b) return "Games can't end in a tie.";
  return null;
}
