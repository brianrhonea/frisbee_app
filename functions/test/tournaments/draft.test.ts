import { describe, expect, it } from "vitest";

import {
  autoPick,
  available,
  onTheClock,
  type PoolPlayer,
  pickProblem,
  snakeIndex,
  startProblem,
  teamsFromDraft,
} from "../../src/tournaments/draft_model";

const p = (uid: string, skill: number, gender: "mmp" | "wmp" | null = null): PoolPlayer => ({
  uid,
  name: uid.toUpperCase(),
  skill,
  gender,
});

describe("snakeIndex", () => {
  // The same table is in test/domain/live_draft_test.dart.
  it("snakes back and forth", () => {
    expect([...Array(9).keys()].map((i) => snakeIndex(3, i))).toEqual([0, 1, 2, 2, 1, 0, 0, 1, 2]);
    expect([...Array(6).keys()].map((i) => snakeIndex(2, i))).toEqual([0, 1, 1, 0, 0, 1]);
  });
});

describe("onTheClock", () => {
  const caps = ["a", "b", "c"];
  it("follows the snake and ends with the pool", () => {
    expect(onTheClock(caps, [], 4)).toBe("a");
    expect(onTheClock(caps, [{ uid: "x", captainId: "a" }], 4)).toBe("b");
    const three = ["x", "y", "z"].map((uid, i) => ({ uid, captainId: caps[i] }));
    expect(onTheClock(caps, three, 4)).toBe("c");
    expect(onTheClock(caps, [...three, { uid: "w", captainId: "c" }], 4)).toBeNull();
  });
});

describe("pickProblem", () => {
  const base = {
    status: "live",
    captainIds: ["a", "b"],
    picks: [{ uid: "x", captainId: "a" }],
    pool: [p("x", 3), p("y", 3), p("z", 3)],
    uid: "y",
  };
  it("allows a free player while live", () => expect(pickProblem(base)).toBeNull());
  it("refuses a double pick, a stranger, and a paused or finished draft", () => {
    expect(pickProblem({ ...base, uid: "x" })).toMatch(/already/);
    expect(pickProblem({ ...base, uid: "q" })).toMatch(/isn't in/);
    expect(pickProblem({ ...base, status: "paused" })).toMatch(/paused/);
    expect(pickProblem({ ...base, status: "done" })).toMatch(/isn't running/);
  });
});

describe("autoPick", () => {
  it("takes the best player left, lowest uid on a tie", () => {
    expect(autoPick([p("b", 3), p("a", 3), p("c", 2)], [], false)?.uid).toBe("a");
    expect(autoPick([], [], false)).toBeNull();
  });
  it("evens out gender in a mixed division", () => {
    const left = [p("m1", 5, "mmp"), p("w1", 3, "wmp")];
    expect(autoPick(left, [p("cap", 4, "mmp")], true)?.uid).toBe("w1");
    expect(autoPick(left, [p("cap", 4, "wmp")], true)?.uid).toBe("m1");
    // Falls back to anyone if that match has run out.
    expect(autoPick([p("m1", 5, "mmp")], [p("cap", 4, "mmp")], true)?.uid).toBe("m1");
  });
});

describe("available and startProblem", () => {
  it("drops picked players", () => {
    expect(available([p("a", 1), p("b", 1)], [{ uid: "a", captainId: "c" }]).map((x) => x.uid)).toEqual(["b"]);
  });
  it("checks captains and pool", () => {
    const accepted = new Set(["a", "b", "c", "d"]);
    expect(startProblem({ captainIds: ["a", "b"], accepted, poolSize: 2 })).toBeNull();
    expect(startProblem({ captainIds: ["a"], accepted, poolSize: 3 })).toMatch(/at least/);
    expect(startProblem({ captainIds: ["a", "a"], accepted, poolSize: 3 })).toMatch(/twice/);
    expect(startProblem({ captainIds: ["a", "z"], accepted, poolSize: 3 })).toMatch(/accepted/);
    expect(startProblem({ captainIds: ["a", "b", "c"], accepted, poolSize: 1 })).toMatch(/enough/);
  });
});

describe("teamsFromDraft", () => {
  it("puts each captain first on their own team", () => {
    const teams = teamsFromDraft({
      captains: [
        { uid: "a", name: "Ana" },
        { uid: "b", name: "Ben" },
      ],
      picks: [
        { uid: "x", captainId: "a" },
        { uid: "y", captainId: "b" },
        { uid: "z", captainId: "b" },
      ],
      names: { x: "Xi", y: "Yo", z: "Zed" },
    });
    expect(teams.map((t) => t.id)).toEqual(["team1", "team2"]);
    expect(teams[0]).toMatchObject({ name: "Team Ana", captainId: "a", playerIds: ["a", "x"] });
    expect(teams[1].playerIds).toEqual(["b", "y", "z"]);
    expect(teams[1].playerNames).toEqual({ b: "Ben", y: "Yo", z: "Zed" });
  });
});
