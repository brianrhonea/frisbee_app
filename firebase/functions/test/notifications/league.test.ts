import { describe, expect, it } from "vitest";

import { draftDeliveries, signupDecisionNotice } from "../../src/notifications/league";
import type { Prefs } from "../../src/notifications/model";

const prefs = {} as Prefs;
const ids = { tournamentId: "t1", divisionId: "d1", eventName: "Thursday Night" };
const board = (over: Record<string, unknown> = {}) => ({
  status: "live",
  captains: [
    { uid: "a", name: "Ana" },
    { uid: "b", name: "Ben" },
  ],
  pool: { x: "Xi", y: "Yo", z: "Zed" },
  picks: [] as { uid: string; captainId: string }[],
  pickSeconds: 60,
  ...over,
});

describe("draftDeliveries", () => {
  it("tells the captains and the pool when it starts", () => {
    const out = draftDeliveries({ ...ids, before: undefined, after: board() });
    const ana = out.find((d) => d.uids.includes("a"))!;
    const ben = out.find((d) => d.uids.includes("b"))!;
    expect(ana.notice.text(prefs, 1)).toEqual({
      title: "Thursday Night: you're a captain",
      body: "The draft is live and you pick first.",
    });
    expect(ben.notice.text(prefs, 1).body).toBe("The draft is live. Ana picks first.");
    const pool = out.find((d) => d.uids.includes("x"))!;
    expect(pool.uids.sort()).toEqual(["x", "y", "z"]);
    expect(pool.notice.route).toBe("/tournaments/t1/live-draft/d1");
  });

  it("buzzes the captain who's now on the clock, once per turn", () => {
    const before = board();
    const after = board({ picks: [{ uid: "x", captainId: "a" }] });
    const out = draftDeliveries({ ...ids, before, after });
    expect(out).toHaveLength(1);
    expect(out[0].uids).toEqual(["b"]);
    expect(out[0].notice.pushId).toBe("1");
    expect(out[0].notice.text(prefs, 1).body).toContain("60 seconds");
    // Snake: Ben picks again straight away, so no second notice.
    const again = board({
      picks: [
        { uid: "x", captainId: "a" },
        { uid: "y", captainId: "b" },
      ],
    });
    expect(draftDeliveries({ ...ids, before: after, after: again })).toEqual([]);
  });

  it("tells the captain on the clock when the host resumes", () => {
    const out = draftDeliveries({ ...ids, before: board({ status: "paused" }), after: board() });
    expect(out.map((d) => d.uids)).toEqual([["a"]]);
  });

  it("says nothing on pause, when every player is picked, or when cancelled", () => {
    expect(draftDeliveries({ ...ids, before: board(), after: board({ status: "paused" }) })).toEqual([]);
    const all = [
      { uid: "x", captainId: "a" },
      { uid: "y", captainId: "b" },
      { uid: "z", captainId: "b" },
    ];
    expect(draftDeliveries({ ...ids, before: board(), after: board({ status: "done", picks: all }) })).toEqual([]);
    expect(draftDeliveries({ ...ids, before: board(), after: undefined })).toEqual([]);
  });

  it("tells everyone their team when it's finished", () => {
    const picks = [
      { uid: "x", captainId: "a" },
      { uid: "y", captainId: "b" },
      { uid: "z", captainId: "b" },
    ];
    const out = draftDeliveries({
      ...ids,
      before: board({ status: "done", picks }),
      after: board({ status: "finished", picks }),
    });
    expect(out.map((d) => d.uids)).toEqual([
      ["a", "x"],
      ["b", "y", "z"],
    ]);
    expect(out[1].notice.text(prefs, 1).body).toBe("You're on Team Ben.");
    expect(out[1].notice.route).toBe("/tournaments/t1");
  });
});

describe("signupDecisionNotice", () => {
  const decide = (from: string, to: string) =>
    signupDecisionNotice({
      tournamentId: "t1",
      eventName: "Hat Day",
      before: { status: from },
      after: { status: to },
    });

  it("tells the player they're in, waitlisted or declined", () => {
    expect(decide("applied", "accepted")?.text(prefs, 1).body).toContain("You're in Hat Day");
    expect(decide("applied", "waitlisted")?.text(prefs, 1).body).toContain("waitlist");
    expect(decide("applied", "declined")?.text(prefs, 1).body).toContain("wasn't accepted");
  });

  it("stays quiet for the player's own changes", () => {
    expect(decide("applied", "withdrawn")).toBeNull();
    expect(decide("withdrawn", "applied")).toBeNull();
    expect(decide("accepted", "accepted")).toBeNull();
  });
});
