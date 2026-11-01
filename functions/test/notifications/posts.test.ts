import { describe, expect, it } from "vitest";

import {
  followCountChanges,
  followKeys,
  postPreview,
  postRecipients,
  teamPostNotice,
  userPostNotice,
  wants,
} from "../../src/notifications/model";

describe("followKeys", () => {
  it("is the author for a person's post, plus its tournament", () => {
    expect(followKeys({ authorId: "u1", post: {} })).toEqual(["user_u1"]);
    expect(followKeys({ authorId: "u1", post: { tournamentKey: "event_123" } })).toEqual(["user_u1", "event_123"]);
  });

  it("is the team for a team post, not its author", () => {
    expect(followKeys({ teamId: "g1", authorId: "u1", post: { tournamentKey: "tournament_g1_t1" } })).toEqual([
      "team_g1",
      "tournament_g1_t1",
    ]);
  });
});

describe("postRecipients", () => {
  it("dedupes and leaves out the author", () => {
    expect(postRecipients(["a", "b", "a", "me"], "me")).toEqual(["a", "b"]);
  });

  it("keeps members-only posts to members", () => {
    expect(postRecipients(["a", "b", "c"], "me", ["b", "me"])).toEqual(["b"]);
  });
});

describe("postPreview", () => {
  it("sums up a workout", () => {
    expect(postPreview({ kind: "workout", workout: { activity: "run", durationMinutes: 45, distanceKm: 8 } })).toBe(
      "45 min run · 8 km",
    );
    expect(postPreview({ kind: "workout", body: "Felt good", workout: { activity: "gym", durationMinutes: 60 } })).toBe(
      "60 min gym session · Felt good",
    );
  });

  it("uses the title and text, or counts photos", () => {
    expect(postPreview({ title: "Tryouts", body: "Saturday  at\n10" })).toBe("Tryouts: Saturday at 10");
    expect(postPreview({ body: "", images: [{}, {}] })).toBe("📷 2 photos");
    expect(postPreview({ body: "x".repeat(200) })).toHaveLength(120);
  });
});

describe("post notices", () => {
  it("open the post, folding per author", () => {
    const n = userPostNotice({ postId: "p1", post: { authorId: "u1", authorName: "Sam", kind: "workout", workout: { activity: "sprints", durationMinutes: 30 } } });
    expect(n.category).toBe("posts");
    expect(n.route).toBe("/posts/p1");
    expect(n.collapseId).toBe("posts_user_u1");
    expect(n.text({}, 1)).toEqual({ title: "Sam shared a workout", body: "30 min sprint session" });
    expect(n.text({}, 3).title).toBe("Sam: 3 new posts");
  });

  it("open the team page for team posts", () => {
    const n = teamPostNotice({ teamId: "g1", teamName: "Boulder Pickup", post: { body: "Fields are open" } });
    expect(n.route).toBe("/teams/g1");
    expect(n.teamId).toBe("g1");
    expect(n.text({}, 1)).toEqual({ title: "Boulder Pickup posted", body: "Fields are open" });
  });

  it("can be turned off like any category", () => {
    expect(wants({ categories: { posts: false } }, "posts")).toBe(false);
    expect(wants({ teams: { g1: { posts: false } } }, "posts", "g1")).toBe(false);
    expect(wants({}, "posts", "g1")).toBe(true);
  });
});

describe("followCountChanges", () => {
  it("counts a follow for the target and the follower", () => {
    expect(followCountChanges("me", "team_t1", undefined, { notify: false })).toEqual([
      { key: "team_t1", field: "followers", by: 1 },
      { key: "user_me", field: "following", by: 1 },
    ]);
    expect(followCountChanges("me", "team_t1", { notify: false }, undefined)[0].by).toBe(-1);
  });

  it("ignores turning the bell on or off", () => {
    expect(followCountChanges("me", "team_t1", { notify: false }, { notify: true })).toEqual([]);
  });
});
