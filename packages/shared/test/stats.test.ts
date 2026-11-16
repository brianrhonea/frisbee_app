// Ports of apps/mobile/test/domain/stats_test.dart, plus the tracker and
// its save scheduling (GameTrackerViewModel).
import { describe, expect, it } from "vitest";
import {
  type Clock,
  currentHalf,
  formatStat,
  gameWon,
  halftimePoint,
  holder,
  Involvement,
  isMilestone,
  lineSources,
  linesForEvent,
  pointSide,
  SaveQueue,
  saveStatsGameSchema,
  saveStatsTournamentSchema,
  saveRosterPlayerSchema,
  type StatAction,
  type StatPoint,
  type StatsGame,
  type StatsPlayer,
  statColumns,
  statSheet,
  statsGameBody,
  statsGameFrom,
  statsTournamentBody,
  statsTournamentFrom,
  timeoutsLeft,
} from "../src/stats.js";
import { GameTracker } from "../src/stats_tracker.js";

const line = ["a", "b", "c", "d", "e", "f", "g"];
const pt = (p: Partial<StatPoint> & Pick<StatPoint, "startedOn">): StatPoint => ({ line, actions: [], result: null, ...p });
const act = (kind: StatAction["kind"], playerId?: string, throwerId?: string): StatAction => ({
  kind,
  ...(playerId && { playerId }),
  ...(throwerId && { throwerId }),
});
const game = (g: Partial<StatsGame> = {}): StatsGame => ({
  id: "g1",
  opponent: "Rival",
  date: "2026-10-28T18:00:00.000Z",
  gameTo: 15,
  tournamentId: null,
  eventId: null,
  points: [],
  finished: false,
  lines: [],
  timeoutsPerHalf: 2,
  timeouts: [],
  ...g,
});

describe("stat sheet (stats_test.dart)", () => {
  it("scoring: assist/goal +1, throwaway and drop -1, blocks +2/+1", () => {
    const sheet = statSheet([
      pt({ startedOn: "offense", result: "weScored", actions: [act("pickup", "a"), act("catch_", "b", "a"), act("goal", "c", "b")] }),
      pt({
        startedOn: "defense",
        result: "theyScored",
        actions: [
          act("beat", "d"),
          act("handBlock", "e"),
          act("pickup", "a"),
          act("throwaway", "a"),
          act("breakup", "b"),
          act("pickup", "a"),
          act("drop", "c", "a"),
        ],
      }),
    ]);
    const p = (id: string) => sheet.players.get(id)!;
    expect(p("b").assists).toBe(1);
    expect(p("c").goals).toBe(1);
    expect(p("b").plusMinus).toBe(2);
    expect(p("c").plusMinus).toBe(0);
    expect(p("a").plusMinus).toBe(-1);
    expect(p("e").plusMinus).toBe(2);
    expect(p("d").plusMinus).toBe(-1);
    expect(p("a").pointsO).toBe(1);
    expect(p("a").pointsD).toBe(1);
  });

  it("touches, completion % and catch %", () => {
    const sheet = statSheet([
      pt({ startedOn: "offense", actions: [act("pickup", "a"), act("catch_", "b", "a"), act("catch_", "a", "b"), act("drop", "b", "a")] }),
    ]);
    const a = sheet.players.get("a")!;
    const b = sheet.players.get("b")!;
    expect(a.touches).toBe(2);
    expect(a.throws).toBe(2);
    expect(a.completionPct).toBe(1);
    expect(b.catchPct).toBe(0.5);
    expect(sheet.players.get("c")!.catchPct).toBeNull();
  });

  it("point side and holder follow turnovers", () => {
    const point = pt({ startedOn: "offense", actions: [act("pickup", "a"), act("catch_", "b", "a")] });
    expect(pointSide(point)).toBe("offense");
    expect(holder(point)).toBe("b");
    const turned = { ...point, actions: [...point.actions, act("throwaway", "b")] };
    expect(pointSide(turned)).toBe("defense");
    expect(holder(turned)).toBeNull();
  });

  it("O efficiency and break rate, scaled up for involvement", () => {
    const sheet = statSheet([
      pt({ startedOn: "offense", result: "weScored", actions: [act("pickup", "a"), act("catch_", "b", "a"), act("goal", "c", "b")] }),
      pt({ startedOn: "offense", result: "theyScored" }),
      pt({ startedOn: "defense", result: "weScored", actions: [act("handBlock", "d"), act("pickup", "d"), act("goal", "e", "d")] }),
      pt({ startedOn: "defense" }),
    ]);
    expect(sheet.team.oPoints).toBe(2);
    expect(sheet.team.holds).toBe(1);
    expect(sheet.team.oEfficiency).toBe(0.5);
    expect(sheet.team.breakRate).toBe(1);
    const p = (id: string) => sheet.players.get(id)!;
    expect(p("g").oEfficiency).toBe(0.5);
    expect(p("g").oRating).toBeCloseTo(0.5, 9);
    expect(p("c").oRating).toBeCloseTo(0.8, 9);
    expect(p("b").oRating).toBeCloseTo(0.8, 9);
    expect(p("d").dEfficiency).toBe(1);
    expect(p("d").dRating).toBeCloseTo(2.6, 9);
    expect(p("a").dRating).toBeCloseTo(1, 9);
    expect(p("a").pointsD).toBe(2);
    expect(p("a").finishedD).toBe(1);
  });

  it("point credit: no touch cap, nothing unless we score, turnovers cost", () => {
    const inv = (f: Partial<Involvement>) => Object.assign(new Involvement(), f);
    expect(inv({ touches: 12 }).credit(true)).toBeCloseTo(2.2, 9);
    expect(inv({ handBlocks: 1 }).credit(false) + 0).toBe(0);
    expect(inv({ touches: 3, goals: 1, throwaways: 1 }).credit(true)).toBeCloseTo(1.05, 9);
    expect(inv({ throwaways: 1, drops: 1 }).credit(false)).toBeCloseTo(-1.5, 9);
  });

  it("games and tournaments survive a save and load", () => {
    const g = game({
      gameTo: 13,
      tournamentId: "t1",
      eventId: "e1",
      finished: true,
      timeoutsPerHalf: 3,
      timeouts: [{ ours: false, half: 2, point: 4, action: 1 }],
      lines: [
        { id: "l1", name: "O", players: line, side: "offense" },
        { id: "l2", name: "Any", players: line, side: null },
      ],
      points: [
        pt({
          startedOn: "defense",
          result: "weScored",
          actions: [
            { kind: "pull", playerId: "a", hangTimeMs: 5400, outOfBounds: true },
            { kind: "sub", playerId: "h", subOutId: "b" },
            act("goal", "c", "h"),
          ],
        }),
        pt({ startedOn: "offense" }),
      ],
    });
    // Through the request schema (what the API stores) and back.
    const stored = saveStatsGameSchema.parse(statsGameBody(g));
    const back = statsGameFrom("g1", { ...stored, date: new Date(stored.date) });
    expect(back).toEqual(g);
    expect(back.points[0].actions[0].hangTimeMs).toBe(5400);
    expect(back.points[1].result).toBeNull();
    expect(back.lines[1].side).toBeNull();
    expect(back.timeouts[0].ours).toBe(false);

    const t = { id: "t1", name: "Regionals", startDate: "2026-10-01T00:00:00.000Z", location: "", eventId: "e2", roster: line, lines: g.lines };
    expect(statsTournamentFrom("t1", saveStatsTournamentSchema.parse(statsTournamentBody(t)))).toEqual(t);
  });

  it("reads loose docs with the app's defaults", () => {
    const g = statsGameFrom("x", { points: [{ actions: [{ kind: "nope", outOfBounds: false }], result: "odd" }], lines: [{ side: "weird" }] });
    expect(g.gameTo).toBe(15);
    expect(g.timeoutsPerHalf).toBe(2);
    expect(g.points[0]).toEqual({ line: [], startedOn: "offense", actions: [{ kind: "catch_" }], result: "weScored" });
    expect(g.lines[0].side).toBe("offense");
  });
});

describe("games", () => {
  it("halftime, timeouts left and the result", () => {
    const scored = (n: number, r: "weScored" | "theyScored") => Array.from({ length: n }, () => pt({ startedOn: "offense", result: r }));
    const g = game({ gameTo: 15, points: [...scored(7, "weScored"), ...scored(1, "theyScored"), ...scored(1, "weScored")] });
    expect(halftimePoint(g)).toBe(8);
    expect(currentHalf(g)).toBe(2);
    expect(timeoutsLeft({ ...g, timeouts: [{ ours: true, half: 1, point: 0, action: 0 }, { ours: true, half: 2, point: 9, action: 0 }] }, true)).toBe(1);
    expect(gameWon(g)).toBeNull();
    expect(gameWon({ ...g, finished: true })).toBe(true);
  });

  it("finds lines for the same event, newest first, without duplicates", () => {
    const l = { id: "l", name: "O", players: line, side: "offense" as const };
    const sources = lineSources(
      [{ id: "t", name: "T", startDate: "2026-01-02T00:00:00Z", location: "", eventId: "e", roster: [], lines: [l] }],
      [game({ id: "g2", date: "2026-01-03T00:00:00Z", eventId: "e", lines: [{ ...l, id: "l2" }] }), game({ id: "g3", tournamentId: "t", lines: [l] })],
    );
    expect(sources.map((s) => s.id)).toEqual(["g2", "t"]);
    expect(linesForEvent("e", sources)).toHaveLength(1);
    expect(linesForEvent(null, sources)).toEqual([]);
  });

  it("formats cells as the app does", () => {
    const sheet = statSheet([pt({ startedOn: "defense", actions: [{ kind: "pull", playerId: "a", hangTimeMs: 5000 }] })]);
    const a = sheet.players.get("a")!;
    const col = (label: string) => statColumns.find((c) => c.label === label)!;
    expect(formatStat(col("HANG"), a)).toBe("5.0");
    expect(formatStat(col("CMP%"), a)).toBe("–");
    expect(formatStat(col("PUL"), a)).toBe("1");
  });
});

describe("request schemas", () => {
  it("bound what the rules leave open and keep the stored shape", () => {
    expect(saveStatsGameSchema.safeParse(statsGameBody(game({ gameTo: 51 }))).success).toBe(false);
    expect(saveStatsGameSchema.safeParse({ ...statsGameBody(game()), extra: 1 }).success).toBe(false);
    const p = saveStatsGameSchema.parse({ ...statsGameBody(game()), points: [{ line, startedOn: "offense", actions: [{ kind: "pull", outOfBounds: false }] }] });
    expect(p.points[0].actions[0]).toEqual({ kind: "pull" });
    expect(saveStatsGameSchema.safeParse({ ...statsGameBody(game()), date: "10000-01-01T00:00:00Z" }).success).toBe(false);
    expect(saveRosterPlayerSchema.parse({ name: " Sam " })).toEqual({ name: "Sam", number: null, position: "hybrid", userId: null });
  });
});

/** A clock tests drive by hand. */
class TestClock implements Clock {
  t = 0;
  timers: Array<{ at: number; fn: () => void; id: number }> = [];
  private n = 0;
  now() {
    return this.t;
  }
  setTimeout(fn: () => void, ms: number) {
    const id = ++this.n;
    this.timers.push({ at: this.t + ms, fn, id });
    return id;
  }
  clearTimeout(h: unknown) {
    this.timers = this.timers.filter((x) => x.id !== h);
  }
  async advance(ms: number) {
    const end = this.t + ms;
    for (;;) {
      this.timers.sort((a, b) => a.at - b.at);
      const next = this.timers[0];
      if (!next || next.at > end) break;
      this.timers.shift();
      this.t = next.at;
      next.fn();
      await new Promise((r) => setImmediate(r));
    }
    this.t = end;
  }
}

describe("SaveQueue", () => {
  const timings = { delayMs: 3000, minGapMs: 1000, backoffMs: 2000, maxBackoffMs: 30_000 };

  it("waits for plays, sends milestones at once, and never sends twice in a gap", async () => {
    const clock = new TestClock();
    const sent: Array<[number, string]> = [];
    const q = new SaveQueue<string>(async (v) => void sent.push([clock.t, v]), undefined, timings, clock);
    q.schedule("tap1", false);
    await clock.advance(1000);
    q.schedule("tap2", false); // doesn't reset the 3 s wait
    await clock.advance(2000);
    expect(sent).toEqual([[3000, "tap2"]]);
    q.schedule("point", true);
    await clock.advance(1000);
    expect(sent[1]).toEqual([4000, "point"]);
    // Hammering milestones: one a second at most, latest wins.
    for (let i = 0; i < 50; i++) {
      q.schedule(`undo${i}`, true);
      await clock.advance(100);
    }
    await clock.advance(2000);
    const gaps = sent.slice(1).map(([t], i, all) => (i === 0 ? Infinity : t - all[i - 1][0]));
    expect(Math.min(...gaps)).toBeGreaterThanOrEqual(1000);
    expect(sent[sent.length - 1][1]).toBe("undo49");
    expect(sent.length).toBeLessThanOrEqual(2 + 7);
  });

  it("keeps a failed save and retries with backoff", async () => {
    const clock = new TestClock();
    let fail = 2;
    const sent: number[] = [];
    const errors: unknown[] = [];
    const q = new SaveQueue<string>(
      async () => {
        sent.push(clock.t);
        if (fail-- > 0) throw new Error("429");
      },
      (e) => errors.push(e),
      timings,
      clock,
    );
    q.schedule("x", true);
    await clock.advance(10_000);
    expect(sent).toEqual([0, 2000, 6000]);
    expect(errors.at(-1)).toBeNull();
    expect(q.dirty).toBe(false);
  });
});

describe("GameTracker (game_tracker_viewmodel.dart)", () => {
  const players: StatsPlayer[] = [..."abcdefgh"].map((id, i) => ({ id, name: id.toUpperCase(), number: i, position: "hybrid", userId: null }));
  const setup = (g = game(), canEdit = true) => {
    const saves: Array<{ g: StatsGame; milestone: boolean }> = [];
    let n = 0;
    const tr = new GameTracker(g, { canEdit, players, tournaments: [], otherGames: [] }, {
      saveGame: (x, milestone) => saves.push({ g: x, milestone }),
      saveTournament: () => undefined,
      newId: () => `id${++n}`,
    });
    return { tr, saves };
  };

  it("tracks an O point: pickup, catches, score, then we pull", () => {
    const { tr, saves } = setup();
    tr.fillDraft(line);
    tr.startDraft();
    expect(saves.at(-1)!.milestone).toBe(true);
    tr.tapPlayer("a");
    tr.tapPlayer("b");
    expect(saves.at(-1)!.milestone).toBe(false);
    expect(tr.holder).toBe("b");
    tr.arm("goal");
    tr.tapPlayer("b"); // the holder can't catch their own throw
    tr.tapPlayer("c");
    expect(saves.at(-1)!.milestone).toBe(true);
    expect(tr.points[0].result).toBe("weScored");
    expect(tr.points[0].actions.at(-1)).toEqual({ kind: "goal", playerId: "c", throwerId: "b" });
    expect(tr.nextSide).toBe("defense");
    expect(tr.undoLabel).toBe("Score: B → C in the endzone");
  });

  it("records a D point with a pull, a block and their score; undo walks back", () => {
    const { tr } = setup(game({ points: [pt({ startedOn: "offense", result: "weScored" })] }));
    tr.useLine(line);
    expect(tr.canPull).toBe(true);
    tr.recordPull("a", 5400, true);
    tr.arm("breakup");
    tr.tapPlayer("d");
    expect(tr.side).toBe("offense");
    tr.tapPlayer("d");
    tr.throwaway();
    tr.theyScored();
    expect(tr.points[1].actions.map((a) => a.kind)).toEqual(["pull", "breakup", "pickup", "throwaway"]);
    expect(tr.points[1].result).toBe("theyScored");
    tr.undo();
    expect(tr.points[1].result).toBeNull();
    tr.undo();
    tr.undo();
    expect(tr.points[1].actions.map((a) => a.kind)).toEqual(["pull", "breakup"]);
  });

  it("subs, timeouts and finishing", () => {
    const { tr, saves } = setup();
    tr.useLine(line);
    tr.tapPlayer("a");
    tr.substitute("a", "h");
    expect(tr.holder).toBe("h");
    expect(tr.onField).toContain("h");
    tr.callTimeout(true);
    expect(tr.game.timeouts).toEqual([{ ours: true, half: 1, point: 0, action: 2 }]);
    expect(saves.at(-1)!.milestone).toBe(true);
    tr.setFinished(true);
    expect(tr.over).toBe(true);
    tr.tapPlayer("b");
    expect(tr.points[0].actions).toHaveLength(2);
  });

  it("older changes undo one action at a time; viewers change nothing", () => {
    const g = game({ points: [pt({ startedOn: "offense", result: "weScored", actions: [act("pickup", "a"), act("goal", "b", "a")] })] });
    const { tr } = setup(g);
    expect(tr.undoLabel).toBe("Score: A → B in the endzone");
    tr.undo();
    expect(tr.points[0]).toMatchObject({ result: null, actions: [act("pickup", "a")] });
    const viewer = setup(g, false);
    viewer.tr.undo();
    viewer.tr.theyScored();
    expect(viewer.saves).toEqual([]);
  });

  it("milestones: only a longer action list on the same point waits", () => {
    const g = game({ points: [pt({ startedOn: "offense" })] });
    const longer = { ...g, points: [{ ...g.points[0], actions: [act("pickup", "a")] }] };
    expect(isMilestone(g, longer)).toBe(false);
    expect(isMilestone(longer, g)).toBe(true);
    expect(isMilestone(g, { ...longer, gameTo: 13 })).toBe(true);
    expect(isMilestone(g, { ...g, finished: true })).toBe(true);
  });
});
