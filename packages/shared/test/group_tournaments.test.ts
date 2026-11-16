// The app's tournament engine tests (apps/mobile/test/domain/
// tournament_engine_test.dart and placement_bracket_test.dart), ported.
import { describe, expect, it } from "vitest";
import {
  type GroupGame,
  type GroupSlotFill,
  type GroupTournamentFormat,
  type GroupTournamentSettings,
  groupEngine as e,
  groupTournamentFormats,
  readGroupGame,
  saveGroupTournamentRequestSchema,
} from "../src/group_tournaments.js";

const start = new Date(2026, 10, 7, 9).toISOString();
const at = (iso: string, minutes: number) => new Date(Date.parse(iso) + minutes * 60_000).toISOString();

function settings(format: GroupTournamentFormat, o: Partial<GroupTournamentSettings> = {}): GroupTournamentSettings {
  return {
    format,
    playersOnField: 5,
    poolCount: 2,
    gameMinutes: 30,
    breakMinutes: 10,
    scoreCap: 11,
    timeoutsPerHalf: 1,
    fields: 2,
    startsAt: start,
    idealEndsAt: null,
    laterDays: [],
    scoring: "points",
    ...o,
  };
}
const teamsOf = (n: number) => Array.from({ length: n }, (_, i) => `T${i + 1}`);
const plan = (n: number, format: GroupTournamentFormat, o: Partial<GroupTournamentSettings> = {}) => e.scheduleFor(teamsOf(n), settings(format, o));

function apply(byId: Map<string, GroupGame>, fills: GroupSlotFill[]) {
  for (const f of fills) {
    const g = byId.get(f.gameId)!;
    byId.set(f.gameId, { ...g, teamA: f.teamA ?? g.teamA, teamB: f.teamB ?? g.teamB });
  }
}

/** Plays every game as soon as both teams are known, applying fills and seeds like the app. */
function playOut(games: GroupGame[], winner?: (g: GroupGame) => string): GroupGame[] {
  const byId = new Map(games.map((g) => [g.id, g]));
  const pick = winner ?? ((g: GroupGame) => (Number(g.teamA!.slice(1)) < Number(g.teamB!.slice(1)) ? g.teamA! : g.teamB!));
  for (let guard = 0; guard < 500; guard++) {
    const list = [...byId.values()].sort((a, b) => a.order - b.order);
    const next = e.gamesToPlay(list).find(e.hasTeams);
    if (!next) {
      const seeds = e.bracketSeeds(list);
      if (seeds.length === 0) return list;
      apply(byId, seeds);
      continue;
    }
    const aWins = pick(next) === next.teamA;
    const done: GroupGame = { ...next, status: "done", scoreA: aWins ? 11 : 7, scoreB: aWins ? 7 : 11 };
    byId.set(next.id, done);
    apply(byId, e.fillsAfter(done, [...byId.values()]));
  }
  throw new Error("Tournament never finished");
}

function losses(games: GroupGame[]) {
  const l = new Map<string, number>();
  for (const g of games.filter(e.isDone)) l.set(e.loserOf(g)!, (l.get(e.loserOf(g)!) ?? 0) + 1);
  return l;
}

describe("team builder", () => {
  it("deals everyone into the teams, differing by at most one", () => {
    const players = Array.from({ length: 23 }, (_, i) => ({ uid: `u${i}`, name: `P${i}` }));
    const named = e.blankTeams(4);
    named[0] = { ...named[0]!, name: "Discs" };
    let seed = 1;
    const teams = e.dealPlayers(players, named, () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646);
    const sizes = teams.map((t) => t.playerIds.length);
    expect(Math.max(...sizes) - Math.min(...sizes)).toBeLessThanOrEqual(1);
    expect(new Set(teams.flatMap((t) => t.playerIds)).size).toBe(23);
    for (const t of teams) expect(t.playerIds).toContain(t.captainId);
    expect(teams.map((t) => t.name)).toEqual(["Discs", "Team 2", "Team 3", "Team 4"]);
    expect(teams.map((t) => t.id)).toEqual(["team1", "team2", "team3", "team4"]);
  });

  it("replaces rosters, ignores duplicates, leaves extra teams empty", () => {
    const old = e.movePlayer(e.blankTeams(3), { uid: "z", name: "Z" }, "team3");
    const teams = e.dealPlayers(
      [
        { uid: "a", name: "A" },
        { uid: "a", name: "A" },
        { uid: "b", name: "B" },
      ],
      old,
    );
    expect(teams.flatMap((t) => t.playerIds).sort()).toEqual(["a", "b"]);
    expect(teams[2]!.playerIds).toEqual([]);
    expect(teams[2]!.captainId).toBeNull();
  });

  it("moving players keeps one team each and a captain", () => {
    let teams = e.blankTeams(2);
    teams = e.movePlayer(teams, { uid: "a", name: "A" }, "team1");
    teams = e.movePlayer(teams, { uid: "b", name: "B" }, "team1");
    expect(teams[0]!.captainId).toBe("a");
    teams = e.movePlayer(teams, { uid: "a", name: "A" }, "team2");
    expect(teams[0]!.playerIds).toEqual(["b"]);
    expect(teams[0]!.captainId).toBe("b");
    expect(teams[1]!.captainId).toBe("a");
    teams = e.movePlayer(teams, { uid: "a", name: "A" }, null);
    expect(teams[1]!.playerIds).toEqual([]);
    expect(teams[1]!.captainId).toBeNull();
    expect(e.blankTeams(1, teams)[0]!.id).toBe("team3");
  });
});

describe("round robin", () => {
  for (const n of [2, 3, 4, 5, 8]) {
    it(`${n} teams: every pair plays once, nobody twice a round`, () => {
      const pairs = new Set<string>();
      for (const round of e.roundRobin(Array.from({ length: n }, (_, i) => i))) {
        const seen = new Set<number>();
        for (const [a, b] of round) {
          expect(seen.has(a) || seen.has(b)).toBe(false);
          seen.add(a).add(b);
          const key = `${Math.min(a, b)}-${Math.max(a, b)}`;
          expect(pairs.has(key)).toBe(false);
          pairs.add(key);
        }
      }
      expect(pairs.size).toBe((n * (n - 1)) / 2);
    });
  }

  it("the best record wins", () => {
    const games = playOut(plan(5, "roundRobin").games);
    expect(games).toHaveLength(10);
    expect(games.every((g) => g.label.startsWith("Round"))).toBe(true);
    expect(e.championOf("roundRobin", games)).toBe("T1");
  });
});

it("seed order spreads the top seeds", () => {
  expect(e.seedOrder(8)).toEqual([1, 8, 4, 5, 2, 7, 3, 6]);
  expect(e.seedOrder(4)).toEqual([1, 4, 2, 3]);
});

describe("single elimination", () => {
  for (const n of [2, 3, 5, 6, 7, 8, 12]) {
    it(`${n} teams: n-1 games, one champion`, () => {
      const p = plan(n, "singleElim");
      expect(p.games).toHaveLength(n - 1);
      const games = playOut(p.games);
      const l = losses(games);
      expect(l.size).toBe(n - 1);
      expect([...l.values()].every((v) => v === 1)).toBe(true);
      expect(e.championOf("singleElim", games)).toBe("T1");
    });
  }

  it("labels the last rounds", () => {
    const games = plan(8, "singleElim").games;
    expect(games.filter((g) => g.label === "Quarterfinal")).toHaveLength(4);
    expect(games.filter((g) => g.label === "Semifinal")).toHaveLength(2);
    expect(games.filter((g) => g.label === "Final")).toHaveLength(1);
  });

  it("an upset still finishes", () => {
    const games = playOut(plan(6, "singleElim").games, (g) => (g.teamA === "T1" ? g.teamB! : g.teamB === "T1" ? g.teamA! : g.teamA!));
    const champ = e.championOf("singleElim", games);
    expect(champ).not.toBe("T1");
    expect(champ).not.toBeNull();
  });
});

describe("double elimination", () => {
  for (const n of [2, 3, 4, 5, 6, 7, 8, 11, 16]) {
    it(`${n} teams: out after two losses, reset only if needed`, () => {
      const p = plan(n, "doubleElim");
      expect(p.games.filter((g) => g.ifNeeded)).toHaveLength(1);
      const games = playOut(p.games);
      const l = losses(games);
      const champ = e.championOf("doubleElim", games)!;
      expect(champ).toBe("T1");
      for (let i = 1; i <= n; i++) expect(l.get(`T${i}`) ?? 0, `T${i}`).toBe(`T${i}` === champ ? 0 : 2);
      const reset = games.find((g) => g.ifNeeded)!;
      expect(e.skippedGame(reset, games)).toBe(true);
      expect(games.filter(e.isDone)).toHaveLength(2 * n - 2);
    });
  }

  it("the reset is played when the losers bracket team wins", () => {
    const games = playOut(plan(4, "doubleElim").games, (g) => {
      if (g.stage === "grandFinal") return g.teamA === "T1" ? g.teamB! : g.teamA!;
      return Number(g.teamA!.slice(1)) < Number(g.teamB!.slice(1)) ? g.teamA! : g.teamB!;
    });
    expect(e.isDone(games.find((g) => g.ifNeeded)!)).toBe(true);
    expect(e.championOf("doubleElim", games)).toBe("T1");
    expect(losses(games).get("T1")).toBe(1);
  });
});

describe("pool play + single elimination", () => {
  it("snake-seeds pools, then seeds the bracket from standings", () => {
    const p = plan(8, "poolsSingleElim");
    const pools = e.poolTeams(p.games);
    expect(new Set(pools.get("A"))).toEqual(new Set(["T1", "T4", "T5", "T8"]));
    expect(new Set(pools.get("B"))).toEqual(new Set(["T2", "T3", "T6", "T7"]));
    expect(p.games.filter((g) => g.stage === "pool")).toHaveLength(12);
    expect(p.games.filter((g) => e.isBracket(g.stage))).toHaveLength(7);
    expect(e.awaitingSeeds(p.games)).toBe(true);
    expect(e.bracketSeeds(p.games)).toEqual([]);
    const games = playOut(p.games);
    expect(e.awaitingSeeds(games)).toBe(false);
    expect(e.championOf("poolsSingleElim", games)).toBe("T1");
    const fin = games.find((g) => g.label === "Final")!;
    expect(new Set([fin.teamA, fin.teamB])).toEqual(new Set(["T1", "T2"]));
  });

  it("odd pools and three teams still work", () => {
    for (const n of [3, 5, 7, 9]) expect(e.championOf("poolsSingleElim", playOut(plan(n, "poolsSingleElim").games)), `${n}`).toBe("T1");
  });
});

describe("scheduler", () => {
  for (const format of groupTournamentFormats) {
    it(`${format}: no team twice a slot, waits for earlier games`, () => {
      const games = playOut(plan(9, format, { fields: 3 }).games);
      const bySlot = new Map<string, GroupGame[]>();
      for (const g of games) bySlot.set(g.startsAt!, [...(bySlot.get(g.startsAt!) ?? []), g]);
      for (const slot of bySlot.values()) {
        expect(slot.length).toBeLessThanOrEqual(3);
        expect(new Set(slot.map((g) => g.field)).size).toBe(slot.length);
        const teams = slot.flatMap((g) => [g.teamA, g.teamB]).filter((t) => t !== null);
        expect(new Set(teams).size).toBe(teams.length);
      }
      const byId = new Map(games.map((g) => [g.id, g]));
      for (const g of games) {
        for (const s of [g.sourceA, g.sourceB]) {
          const deps = !s ? [] : s.type === "pool" ? games.filter((p) => p.pool === s.pool) : [byId.get(s.game)!];
          for (const d of deps) expect(Date.parse(d.startsAt!)).toBeLessThan(Date.parse(g.startsAt!));
        }
      }
    });
  }

  it("slots are game plus break long; warns past the ideal end", () => {
    const p = plan(4, "roundRobin", { idealEndsAt: at(start, 60) });
    expect(new Set(p.games.map((g) => g.startsAt))).toEqual(new Set([start, at(start, 40), at(start, 80)]));
    expect(p.endsAt).toBe(at(start, 110));
    expect(e.overrunMinutes(p, at(start, 60))).toBe(50);
    expect(e.overrunMinutes(p, null)).toBe(0);
  });

  it("splits games evenly over the days", () => {
    expect(e.gamesPerDay(10, 3)).toEqual([4, 3, 3]);
    expect(e.gamesPerDay(6, 2)).toEqual([3, 3]);
    expect(e.gamesPerDay(1, 2)).toEqual([1, 0]);
  });

  it("each day starts at its own time; nothing waits on a later day", () => {
    const day2 = new Date(2026, 10, 8, 10, 30).toISOString();
    const day3 = new Date(2026, 10, 9, 8).toISOString();
    for (const format of groupTournamentFormats) {
      const p = plan(8, format, { laterDays: [day2, day3] });
      expect(p.days.map((d) => d.startsAt)).toEqual([start, day2, day3]);
      const quotas = e.gamesPerDay(p.games.length, 3);
      expect(p.days.map((d) => d.games)).toEqual(quotas);
      let i = 0;
      [start, day2, day3].forEach((dayStart, d) => {
        const games = p.games.slice(i, i + quotas[d]!);
        i += quotas[d]!;
        for (const g of games) expect(Date.parse(g.startsAt!)).toBeGreaterThanOrEqual(Date.parse(dayStart));
        if (games.length) expect(games[0]!.startsAt, format).toBe(dayStart);
      });
      expect(p.endsAt).toBe(p.days[2]!.endsAt);
    }
  });

  it("needs two teams", () => {
    expect(() => plan(1, "singleElim")).toThrow("at least two teams");
  });
});

describe("standings", () => {
  const game = (a: string, b: string, sa: number, sb: number): GroupGame =>
    readGroupGame(`${a}${b}`, { stage: "pool", pool: "A", teamA: a, teamB: b, status: "done", scoreA: sa, scoreB: sb });

  it("wins, then head to head, then point differential", () => {
    const games = [game("a", "b", 11, 9), game("b", "c", 11, 1), game("c", "a", 11, 2), game("d", "a", 0, 11), game("d", "b", 0, 11), game("d", "c", 0, 11)];
    const order = e.standings(["a", "b", "c", "d"], games);
    expect(order.map((s) => s.teamId)).toEqual(["b", "c", "a", "d"]);
    expect(order[0]!.wins).toBe(2);
    expect(order[3]!.losses).toBe(3);
    expect(e.standings(["a", "b"], [game("a", "b", 11, 10)])[0]!.teamId).toBe("a");
  });
});

describe("scores", () => {
  it("rejects ties and out-of-range scores", () => {
    expect(e.scoreError(11, 9)).toBeNull();
    expect(e.scoreError(11, 11)).not.toBeNull();
    expect(e.scoreError(-1, 3)).not.toBeNull();
    expect(e.scoreError(100, 3)).not.toBeNull();
    expect(e.scoreError(null, 3)).not.toBeNull();
  });
});

describe("placement brackets", () => {
  it("ordinal", () => {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 103].map(e.ordinal)).toEqual(["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "103rd"]);
  });

  it("suggested pools follow the usual club formats", () => {
    expect([4, 6, 8, 10, 12, 16, 20].map(e.suggestedPools)).toEqual([1, 1, 2, 2, 3, 4, 4]);
  });

  for (const n of [2, 3, 5, 6, 8, 12, 16]) {
    it(`placement bracket for ${n} teams gives every place once`, () => {
      const seeds = Array.from({ length: n }, (_, i) => `T${i + 1}`);
      const p = e.scheduleFor(seeds, settings("poolsPlacement", { poolCount: n >= 8 ? 2 : 1, fields: 4 }));
      const played = playOut(p.games);
      expect(e.gamesToPlay(played)).toEqual([]);
      expect(e.placementsOf("poolsPlacement", seeds, played)).toEqual(seeds);
      expect(e.championOf("poolsPlacement", played)).toBe("T1");
    });
  }

  it("a 6-team bracket starts with crossovers and labels places", () => {
    const games = plan(6, "poolsPlacement", { poolCount: 1 }).games.filter((g) => g.stage !== "pool");
    expect(games.filter((g) => g.stage === "crossover")).toHaveLength(2);
    const labels = new Set(games.map((g) => g.label));
    for (const l of ["Crossover", "Semifinal", "Final", "3rd place", "5th place"]) expect(labels).toContain(l);
    expect(games.find((g) => g.label === "Final")!.place).toBe(1);
    expect(games.find((g) => g.label === "5th place")!.place).toBe(5);
  });
});

describe("save request", () => {
  const base = { name: "Fall Hat", settings: { startsAt: "2026-11-07T14:00:00.000Z" } };
  it("fills the app's defaults", () => {
    const r = saveGroupTournamentRequestSchema.parse(base);
    expect(r.settings).toMatchObject({ format: "poolsSingleElim", playersOnField: 5, poolCount: 2, gameMinutes: 40, fields: 1, scoring: "points", laterDays: [] });
    expect(r.eventId).toBeNull();
  });
  it("refuses a captain off their team and a player on two teams", () => {
    const team = (id: string, players: string[], captainId: string | null = null) => ({ id, name: id, playerIds: players, captainId });
    expect(saveGroupTournamentRequestSchema.safeParse({ ...base, teams: [team("t1", ["a"], "b")] }).success).toBe(false);
    expect(saveGroupTournamentRequestSchema.safeParse({ ...base, teams: [team("t1", ["a"]), team("t2", ["a"])] }).success).toBe(false);
    expect(saveGroupTournamentRequestSchema.safeParse({ ...base, teams: [team("t1", ["a"]), team("t1", ["b"])] }).success).toBe(false);
    expect(saveGroupTournamentRequestSchema.safeParse({ ...base, teams: [team("t1", ["a"], "a")] }).success).toBe(true);
  });
});
