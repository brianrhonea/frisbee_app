import { describe, expect, it } from "vitest";

import {
  clientIp,
  eventView,
  isPrivateGroup,
  isPrivateProfile,
  listingView,
  parseBefore,
  postAuthors,
  postView,
  profileView,
  searchProfileView,
  teamPostView,
  validId,
  visitorKey,
} from "../../src/browse/model";

describe("visitors", () => {
  it("are keyed by a hash of their IP, never the IP itself", () => {
    const key = visitorKey("203.0.113.9");
    expect(key).toMatch(/^ip_[0-9a-f]{32}$/);
    expect(key).not.toContain("203");
    expect(visitorKey("203.0.113.9")).toBe(key);
    expect(visitorKey("203.0.113.10")).not.toBe(key);
  });

  it("are found by the first forwarded hop, else the socket", () => {
    expect(clientIp("198.51.100.1, 10.0.0.1", "10.0.0.2")).toBe("198.51.100.1");
    expect(clientIp(undefined, "10.0.0.2")).toBe("10.0.0.2");
    expect(clientIp("", undefined)).toBe("unknown");
  });
});

describe("input", () => {
  it("takes only ids the app could have made", () => {
    expect(validId("abc_DEF-123")).toBe(true);
    expect(validId("../profiles")).toBe(false);
    expect(validId("a/b")).toBe(false);
    expect(validId("")).toBe(false);
    expect(validId(7)).toBe(false);
  });

  it("takes a positive cursor or none", () => {
    expect(parseBefore(1700000000000)).toBe(1700000000000);
    expect(parseBefore(-1)).toBeNull();
    expect(parseBefore("1")).toBeNull();
    expect(parseBefore(Number.NaN)).toBeNull();
  });
});

describe("posts", () => {
  const post = {
    kind: "workout",
    body: "Track day",
    authorId: "u1",
    authorName: "Pat",
    likedBy: ["a", "b"],
    repostedBy: ["c"],
    commentCount: 4,
    workout: { activity: "run", distanceKm: 5, route: { points: [[40, -105]] } },
    secret: "nope",
  };

  it("count likes and reposts instead of naming who", () => {
    const view = postView(post);
    expect(view.likeCount).toBe(2);
    expect(view.repostCount).toBe(1);
    expect(view).not.toHaveProperty("likedBy");
    expect(view).not.toHaveProperty("repostedBy");
  });

  it("keep a workout's numbers but not its GPS route", () => {
    expect(postView(post).workout).toEqual({ activity: "run", distanceKm: 5 });
  });

  it("show only allowed fields", () => {
    expect(postView(post)).not.toHaveProperty("secret");
    expect(postView(post).body).toBe("Track day");
  });

  it("depend on their author's privacy, and a repost's original's", () => {
    expect(postAuthors(post)).toEqual(["u1"]);
    expect(postAuthors({ authorId: "u1", repostOf: { postId: "p", authorId: "u2" } })).toEqual(["u1", "u2"]);
  });
});

describe("profiles", () => {
  const profile = {
    name: "Pat",
    username: "pat",
    photoUrl: "https://x/p.png",
    bio: "Handler",
    keywords: ["pat"],
    tags: ["denver"],
    teams: [{ id: "t1" }],
    stats: { season: {} },
    games: [{ id: "g1" }],
    visibility: { stats: false },
  };

  it("missing or private ones are private", () => {
    expect(isPrivateProfile(undefined)).toBe(true);
    expect(isPrivateProfile({ private: true })).toBe(true);
    expect(isPrivateProfile({ name: "Pat" })).toBe(false);
  });

  it("follow the player's visibility settings", () => {
    const view = profileView(profile);
    expect(view.bio).toBe("Handler");
    expect(view.teams).toEqual([{ id: "t1" }]);
    expect(view.games).toEqual([{ id: "g1" }]);
    expect(view).not.toHaveProperty("stats");
    expect(view.visibility).toEqual({ stats: false, teams: true, games: true });
  });

  it("never show search keywords or tags", () => {
    expect(profileView(profile)).not.toHaveProperty("keywords");
    expect(profileView(profile)).not.toHaveProperty("tags");
    expect(searchProfileView(profile)).toEqual({ name: "Pat", photoUrl: "https://x/p.png", username: "pat" });
  });

  it("show only the card when private", () => {
    expect(profileView({ ...profile, private: true })).toEqual({
      name: "Pat",
      photoUrl: "https://x/p.png",
      username: "pat",
      private: true,
    });
    expect(searchProfileView({ ...profile, private: true }).private).toBe(true);
  });
});

describe("teams", () => {
  it("private groups are groups that approve who joins", () => {
    expect(isPrivateGroup(undefined)).toBe(true);
    expect(isPrivateGroup({ kind: "community", requiresApproval: true })).toBe(true);
    expect(isPrivateGroup({ kind: "community", requiresApproval: false })).toBe(false);
    expect(isPrivateGroup({ kind: "team", requiresApproval: true })).toBe(false);
  });

  it("listings, events and posts show only allowed fields", () => {
    expect(listingView({ name: "Riverside", keywords: ["riverside"] })).toEqual({ name: "Riverside" });
    expect(eventView({ title: "Practice", startsAt: 1, responses: { u1: "yes" } })).toEqual({
      title: "Practice",
      startsAt: 1,
    });
    expect(teamPostView({ title: "Tryouts", public: true, reactions: { u1: "x" } })).toEqual({
      title: "Tryouts",
      public: true,
    });
  });
});
