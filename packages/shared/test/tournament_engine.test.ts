// The engine ported from apps/mobile/lib/domain/tournament_engine, checked
// against the app's own cases (test/domain/tournament_engine_test.dart,
// season_test.dart and placement_bracket_test.dart).
import { describe, expect, it } from "vitest";
import {
  bracketSeeds,
  byesIn,
  championOf,
  type EngineGame,
  type EngineSeason,
  type EngineSettings,
  fillsAfter,
  formatOn,
  gamesToPlay,
  laterGamesPlayed,
  ordinal,
  placementsOf,
  roundRobin,
  ScheduleError,
  scheduleFor,
  scoreError,
  seasonFor,
  seasonNights,
  seedOrder,
  standings,
  suggestedPools,
  type TournamentFormat,
  usualFormat,
} from "../src/index.js";

const teams = (n: number) => Array.from({ length: n }, (_, i) => `t${i + 1}`);
const settings = (o: Partial<EngineSettings> = {}): EngineSettings => ({
  format: "roundRobin",
  playersOnField: 7,
  poolCount: 2,
  gameMinutes: 60,
  breakMinutes: 10,
  scoreCap: 15,
  timeoutsPerHalf: 1,
  fields: 2,
  startsAt: new Date(2026, 5, 6, 9),
  idealEndsAt: null,
  laterDays: [],
  scoring: "points",
  ...o,
});
const season = (o: Partial<EngineSeason> = {}): EngineSeason => ({ weeks: 8, playoffWeeks: 0, playoffTeams: 0, gamesPerNight: 1, skipDates: [], ...o });

/** Plays every game in order, the lower seed number winning (teams are t1, t2...), filling slots as it goes. */
function playOut(games: EngineGame[], upset = (_g: EngineGame) => false): EngineGame[] {
  let list = games.map((g) => ({ ...g }));
  for (let guard = 0; guard < 1000; guard++) {
    for (const f of bracketSeeds(list)) {
      list = list.map((g) => (g.id === f.gameId ? { ...g, teamA: f.teamA ?? g.teamA, teamB: f.teamB ?? g.teamB } : g));
    }
    const next = gamesToPlay(list).find((g) => g.teamA != null && g.teamB != null);
    if (!next) break;
    const aWins = Number((next.teamA as string).slice(1)) < Number((next.teamB as string).slice(1)) !== upset(next);
    const done: EngineGame = { ...next, status: "done", scoreA: aWins ? 15 : 10, scoreB: aWins ? 10 : 15 };
    list = list.map((g) => (g.id === done.id ? done : g));
    for (const f of fillsAfter(done, list)) {
      list = list.map((g) => (g.id === f.gameId ? { ...g, teamA: f.teamA ?? g.teamA, teamB: f.teamB ?? g.teamB } : g));
    }
  }
  return list;
}

describe("round robin", () => {
  for (const n of [2, 3, 4, 5, 6, 7, 8]) {
    it(`${n} teams: every pair plays once, nobody twice a round`, () => {
      const rounds = roundRobin(teams(n));
      const pairs = new Set<string>();
      for (const r of rounds) {
        const seen = new Set<string>();
        for (const [a, b] of r) {
          expect(seen.has(a) || seen.has(b)).toBe(false);
          seen.add(a);
          seen.add(b);
          pairs.add([a, b].sort().join("-"));
        }
      }
      expect(pairs.size).toBe((n * (n - 1)) / 2);
    });
  }

  it("the best record wins", () => {
    const plan = scheduleFor(teams(4), settings());
    expect(championOf("roundRobin", playOut(plan.games))).toBe("t1");
  });
});

describe("brackets", () => {
  it("seed order spreads the top seeds", () => {
    expect(seedOrder(8)).toEqual([1, 8, 4, 5, 2, 7, 3, 6]);
  });

  for (const n of [2, 3, 5, 8, 11, 16]) {
    it(`single elimination with ${n} teams: n-1 games, one champion`, () => {
      const plan = scheduleFor(teams(n), settings({ format: "singleElim" }));
      expect(plan.games).toHaveLength(n - 1);
      expect(championOf("singleElim", playOut(plan.games))).toBe("t1");
    });
  }

  it("labels the last rounds", () => {
    const labels = scheduleFor(teams(8), settings({ format: "singleElim" })).games.map((g) => g.label);
    expect(labels.filter((l) => l === "Quarterfinal")).toHaveLength(4);
    expect(labels.filter((l) => l === "Semifinal")).toHaveLength(2);
    expect(labels.at(-1)).toBe("Final");
  });

  for (const n of [4, 6, 8]) {
    it(`double elimination with ${n} teams: reset only if needed`, () => {
      const plan = scheduleFor(teams(n), settings({ format: "doubleElim" }));
      const played = playOut(plan.games);
      expect(championOf("doubleElim", played)).toBe("t1");
      const reset = played.find((g) => g.stage === "reset");
      expect(reset?.status).toBe("scheduled");
      expect(gamesToPlay(played)).toHaveLength(0);
    });
  }

  it("the reset is played when the losers' bracket team wins the final", () => {
    const plan = scheduleFor(teams(4), settings({ format: "doubleElim" }));
    const played = playOut(plan.games, (g) => g.stage === "grandFinal");
    const reset = played.find((g) => g.stage === "reset");
    expect(reset?.status).toBe("done");
  });

  it("pools then a bracket seeded from the standings", () => {
    const plan = scheduleFor(teams(8), settings({ format: "poolsSingleElim", poolCount: 2 }));
    const pools = new Map<string, Set<string>>();
    for (const g of plan.games.filter((x) => x.stage === "pool")) {
      const set = pools.get(g.pool as string) ?? new Set();
      set.add(g.teamA as string).add(g.teamB as string);
      pools.set(g.pool as string, set);
    }
    expect([...(pools.get("A") ?? [])].sort()).toEqual(["t1", "t4", "t5", "t8"]);
    expect(championOf("poolsSingleElim", playOut(plan.games))).toBe("t1");
  });

  for (const n of [4, 5, 6, 8, 12]) {
    it(`a placement bracket for ${n} teams gives every place once`, () => {
      const plan = scheduleFor(teams(n), settings({ format: "poolsPlacement", poolCount: suggestedPools(n) }));
      const places = placementsOf("poolsPlacement", teams(n), playOut(plan.games));
      expect(new Set(places).size).toBe(n);
      expect(places[0]).toBe("t1");
    });
  }

  it("ordinals", () => {
    expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map(ordinal)).toEqual(["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st"]);
  });
});

describe("scheduler", () => {
  for (const format of ["roundRobin", "poolsSingleElim", "singleElim", "doubleElim", "poolsPlacement"] as TournamentFormat[]) {
    it(`${format}: no team twice a slot, waits for earlier games`, () => {
      const plan = scheduleFor(teams(8), settings({ format, fields: 3 }));
      const bySlot = new Map<number, EngineGame[]>();
      for (const g of plan.games) bySlot.set(g.startsAt?.getTime() ?? 0, [...(bySlot.get(g.startsAt?.getTime() ?? 0) ?? []), g]);
      for (const slot of bySlot.values()) {
        expect(slot.length).toBeLessThanOrEqual(3);
        const ids = slot.flatMap((g) => [g.teamA, g.teamB].filter(Boolean));
        expect(new Set(ids).size).toBe(ids.length);
      }
      const start = new Map(plan.games.map((g) => [g.id, g.startsAt?.getTime() ?? 0]));
      for (const g of plan.games) {
        for (const s of [g.sourceA, g.sourceB]) {
          if (s && s.type !== "pool") expect(start.get(s.game) as number).toBeLessThan(start.get(g.id) as number);
        }
      }
      expect(plan.games.map((g) => g.order)).toEqual(plan.games.map((_, i) => i));
    });
  }

  it("slots are game plus break long", () => {
    const plan = scheduleFor(teams(4), settings({ fields: 1 }));
    expect(plan.games[1].startsAt?.getTime()! - plan.games[0].startsAt?.getTime()!).toBe(70 * 60_000);
  });

  it("splits games over the days", () => {
    const day2 = new Date(2026, 5, 7, 8);
    const plan = scheduleFor(teams(6), settings({ laterDays: [day2] }));
    expect(plan.days).toHaveLength(2);
    expect(plan.days[0].games + plan.days[1].games).toBe(plan.games.length);
    expect(plan.games.at(-1)?.startsAt?.getDate()).toBe(7);
  });

  it("needs two teams", () => {
    expect(() => scheduleFor(["t1"], settings())).toThrow(ScheduleError);
  });
});

describe("league season", () => {
  const night = new Date(2026, 2, 3, 18, 30);

  it("nights are a week apart, skipping dates, at the same local time", () => {
    const nights = seasonNights(settings({ startsAt: night }), season({ weeks: 4, skipDates: [new Date(2026, 2, 10)] }));
    expect(nights.map((d) => d.getDate())).toEqual([3, 17, 24, 31]);
    expect(nights.every((d) => d.getHours() === 18 && d.getMinutes() === 30)).toBe(true);
  });

  it("is a weekly round robin in pool A, round = week", () => {
    const plan = seasonFor(teams(4), settings({ startsAt: night }), season({ weeks: 3 }));
    expect(plan.games).toHaveLength(6);
    expect(plan.games.every((g) => g.stage === "pool" && g.pool === "A" && g.label === `Week ${g.round}`)).toBe(true);
  });

  it("an odd number of teams gives a bye each week", () => {
    const plan = seasonFor(teams(5), settings({ startsAt: night }), season({ weeks: 5 }));
    for (let w = 1; w <= 5; w++) expect(byesIn(teams(5), plan.games, w)).toHaveLength(1);
  });

  it("two games a night plays two rounds", () => {
    const plan = seasonFor(teams(4), settings({ startsAt: night }), season({ weeks: 2, gamesPerNight: 2 }));
    expect(plan.games).toHaveLength(8);
    expect(plan.days).toHaveLength(2);
  });

  it("playoffs take the last weeks and fill from the standings", () => {
    const plan = seasonFor(teams(6), settings({ startsAt: night }), season({ weeks: 7, playoffWeeks: 2, playoffTeams: 4 }));
    const bracket = plan.games.filter((g) => g.stage === "winners");
    expect(bracket).toHaveLength(3);
    expect(bracket.at(-1)?.startsAt?.getDate()).toBe(14);
    const played = playOut(plan.games);
    expect(championOf("singleElim", played)).toBe("t1");
  });

  it("the playoffs can't take every week", () => {
    expect(() => seasonFor(teams(4), settings(), season({ weeks: 2, playoffWeeks: 2, playoffTeams: 2 }))).toThrow(ScheduleError);
  });
});

describe("results", () => {
  it("standings: wins, then head to head, then point differential", () => {
    const g = (id: string, a: string, b: string, sa: number, sb: number): EngineGame => ({
      id,
      order: 0,
      stage: "pool",
      round: 1,
      label: "",
      pool: "A",
      field: 1,
      startsAt: null,
      teamA: a,
      teamB: b,
      sourceA: null,
      sourceB: null,
      status: "done",
      scoreA: sa,
      scoreB: sb,
      report: null,
      ifNeeded: false,
    });
    const rows = standings(["a", "b", "c"], [g("1", "a", "b", 10, 15), g("2", "b", "c", 15, 1), g("3", "c", "a", 5, 15)]);
    expect(rows.map((r) => r.teamId)).toEqual(["b", "a", "c"]);
  });

  it("a corrected score replaces filled slots; later played games block it", () => {
    const plan = scheduleFor(teams(4), settings({ format: "singleElim" }));
    const played = playOut(plan.games);
    const semi = played.find((g) => g.label === "Semifinal") as EngineGame;
    expect(laterGamesPlayed(semi, played)).toBe(true);
    const flipped = { ...semi, scoreA: 1, scoreB: 15 };
    const final = played.find((g) => g.label === "Final") as EngineGame;
    const reopened = played.map((x) => (x.id === final.id ? { ...x, status: "scheduled" as const, scoreA: null, scoreB: null } : x));
    expect(fillsAfter(flipped, reopened, true)).toHaveLength(1);
    expect(fillsAfter(flipped, reopened, false)).toHaveLength(0);
  });

  it("scores: no ties, 0 to 99", () => {
    expect(scoreError(15, 15)).toMatch(/tie/);
    expect(scoreError(100, 1)).toMatch(/0 to 99/);
    expect(scoreError(15, 13)).toBeNull();
  });
});

describe("formats", () => {
  it("a league's format follows its season; a tournament gets each later day", () => {
    const start = new Date(2026, 5, 6);
    const end = new Date(2026, 5, 7);
    const t = usualFormat({ kind: "tournament", startsOn: start, endsOn: end });
    expect(t.settings.laterDays).toHaveLength(1);
    expect(t.settings.laterDays[0].getHours()).toBe(9);
    const l = formatOn(usualFormat({ kind: "league", startsOn: start, endsOn: null }), {
      kind: "league",
      startsOn: new Date(2026, 5, 9),
      endsOn: null,
      season: { playoffTeams: 4, playoffWeeks: 1 },
    });
    expect(l.settings.format).toBe("singleElim");
    expect(l.settings.startsAt.getDate()).toBe(9);
    expect(l.settings.startsAt.getHours()).toBe(18);
  });
});
