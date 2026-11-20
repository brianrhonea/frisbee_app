// Live running scores (F1): the request, what counts as live, and when a
// game can take one. Mirrored by LiveScore and GroupGame.liveAt /
// inLiveWindow in apps/mobile/lib/domain/models/group_tournament.dart.
import { describe, expect, it } from "vitest";
import { inLiveWindow, isLiveGame, liveLimits, liveScoreOf, liveScoreRequestSchema } from "../src/tournaments.js";

const now = Date.UTC(2026, 10, 21, 18);
const hour = 3600_000;

describe("liveScoreRequestSchema", () => {
  it("takes two whole scores 0-99, ties included, and nothing else", () => {
    expect(liveScoreRequestSchema.safeParse({ scoreA: 0, scoreB: 0 }).success).toBe(true);
    expect(liveScoreRequestSchema.safeParse({ scoreA: 7, scoreB: 7 }).success).toBe(true);
    expect(liveScoreRequestSchema.safeParse({ scoreA: 99, scoreB: 0 }).success).toBe(true);
    for (const bad of [{ scoreA: 100, scoreB: 0 }, { scoreA: -1, scoreB: 0 }, { scoreA: 1.5, scoreB: 0 }, { scoreA: 1 }, { scoreA: 1, scoreB: 2, by: "x" }]) {
      expect(liveScoreRequestSchema.safeParse(bad).success).toBe(false);
    }
  });
});

describe("isLiveGame", () => {
  const live = (updatedAt: unknown) => ({ scoreA: 3, scoreB: 2, startedAt: updatedAt, updatedAt });
  it("is live while scheduled with a fresh running score", () => {
    expect(isLiveGame({ status: "scheduled", live: live(new Date(now - hour)) }, now)).toBe(true);
    expect(isLiveGame({ status: "scheduled", live: live(new Date(now - hour).toISOString()) }, new Date(now))).toBe(true);
    expect(isLiveGame({ status: "scheduled", live: live(new Date(now - liveLimits.staleAfterMs)) }, now)).toBe(true);
  });
  it("not once stale, reported or final, or without one", () => {
    expect(isLiveGame({ status: "scheduled", live: live(new Date(now - liveLimits.staleAfterMs - 1)) }, now)).toBe(false);
    expect(isLiveGame({ status: "reported", live: live(new Date(now)) }, now)).toBe(false);
    expect(isLiveGame({ status: "done", live: live(new Date(now)) }, now)).toBe(false);
    expect(isLiveGame({ status: "scheduled" }, now)).toBe(false);
    expect(isLiveGame({ status: "scheduled", live: { scoreA: 1 } }, now)).toBe(false);
  });
});

describe("liveScoreOf", () => {
  it("reads the stored map, dates as Date", () => {
    expect(liveScoreOf({ scoreA: 1, scoreB: 2, startedAt: "2026-11-21T17:00:00.000Z", updatedAt: new Date(now), by: "u" })).toEqual({
      scoreA: 1,
      scoreB: 2,
      startedAt: new Date("2026-11-21T17:00:00.000Z"),
      updatedAt: new Date(now),
      by: "u",
    });
    expect(liveScoreOf(null)).toBeNull();
    expect(liveScoreOf({ scoreA: "1", scoreB: 2 })).toBeNull();
  });
});

describe("inLiveWindow", () => {
  it("from two hours before the start to a day after; any time without one", () => {
    const at = new Date(now);
    expect(inLiveWindow(at, now - liveLimits.earlyMs)).toBe(true);
    expect(inLiveWindow(at, now - liveLimits.earlyMs - 1)).toBe(false);
    expect(inLiveWindow(at, now + liveLimits.lateMs)).toBe(true);
    expect(inLiveWindow(at, now + liveLimits.lateMs + 1)).toBe(false);
    expect(inLiveWindow(null, now)).toBe(true);
  });
});
