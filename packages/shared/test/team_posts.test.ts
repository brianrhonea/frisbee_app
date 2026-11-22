// Team feed extras (redesign F24): pinned posts first, comment labels and
// the request schemas.
import { describe, expect, it } from "vitest";
import {
  arrangeTeamFeed,
  pinTeamPostRequestSchema,
  teamPostCommentLabel,
  teamPostCommentRequestSchema,
  teamPostPinsMax,
} from "../src/index.js";

const post = (id: string, createdAt: string, pinnedAt?: string) => ({ id, createdAt, ...(pinnedAt && { pinnedAt }) });

describe("arrangeTeamFeed", () => {
  it("puts pinned posts first, newest pin first, and shows each post once", () => {
    const old = post("old", "2026-11-01T00:00:00Z", "2026-11-19T00:00:00Z");
    const mid = post("mid", "2026-11-10T00:00:00Z", "2026-11-18T00:00:00Z");
    const recent = [post("new", "2026-11-20T00:00:00Z"), mid, post("plain", "2026-11-05T00:00:00Z")];
    const { pinned, rest } = arrangeTeamFeed([mid, old], recent);
    expect(pinned.map((p) => p.id)).toEqual(["old", "mid"]);
    expect(rest.map((p) => p.id)).toEqual(["new", "plain"]);
  });

  it("drops a post unpinned since the pins were read to the rest, and keeps the cap", () => {
    const pins = Array.from({ length: teamPostPinsMax + 1 }, (_, i) =>
      post(`p${i}`, `2026-11-0${i + 1}T00:00:00Z`, `2026-11-1${i}T00:00:00Z`),
    );
    // p0 was unpinned: the main listener's copy has no pinnedAt.
    const { pinned, rest } = arrangeTeamFeed(pins, [post("p0", "2026-11-01T00:00:00Z")]);
    expect(pinned.map((p) => p.id)).toEqual(["p3", "p2", "p1"]);
    expect(rest.map((p) => p.id)).toEqual(["p0"]);
  });

  it("reads Dates as the browser's live reads give them", () => {
    const a = { id: "a", createdAt: new Date("2026-11-01"), pinnedAt: new Date("2026-11-02") };
    const b = { id: "b", createdAt: new Date("2026-11-03"), pinnedAt: null };
    const { pinned, rest } = arrangeTeamFeed([], [b, a]);
    expect(pinned.map((p) => p.id)).toEqual(["a"]);
    expect(rest.map((p) => p.id)).toEqual(["b"]);
  });
});

describe("team post comments", () => {
  it("labels the count, hiding a missing one", () => {
    expect(teamPostCommentLabel(undefined)).toBe("Comment");
    expect(teamPostCommentLabel(0)).toBe("Comment");
    expect(teamPostCommentLabel(-2)).toBe("Comment");
    expect(teamPostCommentLabel(1)).toBe("1 comment");
    expect(teamPostCommentLabel(12)).toBe("12 comments");
  });

  it("trims comments and refuses empty or long ones", () => {
    expect(teamPostCommentRequestSchema.parse({ body: "  nice  " })).toEqual({ body: "nice" });
    expect(teamPostCommentRequestSchema.safeParse({ body: "   " }).success).toBe(false);
    expect(teamPostCommentRequestSchema.safeParse({ body: "x".repeat(1001) }).success).toBe(false);
    expect(teamPostCommentRequestSchema.safeParse({ body: "x", extra: 1 }).success).toBe(false);
  });

  it("takes an optional pin to swap out", () => {
    expect(pinTeamPostRequestSchema.parse({})).toEqual({});
    expect(pinTeamPostRequestSchema.parse({ unpin: "p1" })).toEqual({ unpin: "p1" });
  });
});
