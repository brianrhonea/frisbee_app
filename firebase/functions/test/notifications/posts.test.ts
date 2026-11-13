import { describe, expect, it } from "vitest";

import {
  commentCountChange,
  commentLikeNotice,
  commentNotice,
  commentRecipients,
  replyNotice,
  followCountChanges,
  followerNotice,
  followAcceptedNotice,
  followKeys,
  followRequestNotice,
  likeNotice,
  newLikers,
  repostNotice,
  repostOf,
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

describe("likes, reposts and followers", () => {
  it("finds who newly liked a post, not its author", () => {
    expect(newLikers({ likedBy: ["a"] }, { authorId: "me", likedBy: ["a", "b", "me", "b"] })).toEqual(["b"]);
    expect(newLikers(undefined, { authorId: "me", likedBy: ["a"] })).toEqual(["a"]);
    expect(newLikers({ likedBy: ["a", "b"] }, { authorId: "me", likedBy: ["a"] })).toEqual([]);
  });

  it("folds likes on one post together", () => {
    const n = likeNotice({ postId: "p1", post: { body: "Good throws" }, likerName: "Sam" });
    expect(n.category).toBe("social");
    expect(n.route).toBe("/posts/p1");
    expect(n.collapseId).toBe("likes_p1");
    expect(n.text({}, 1)).toEqual({ title: "Sam liked your post", body: "Good throws" });
    expect(n.text({}, 3).title).toBe("3 new likes on your post");
  });

  it("tells the original's author about a repost", () => {
    const repost = { kind: "repost", authorName: "Zed", body: "Look!", repostOf: { postId: "p1", authorId: "sam", authorName: "Sam" } };
    expect(repostOf(repost)).toEqual({ postId: "p1", authorId: "sam", authorName: "Sam" });
    expect(repostOf({ kind: "text", repostOf: { postId: "p1" } })).toBeUndefined();
    const n = repostNotice({ repostId: "r_p1_zed", repost, original: { body: "Pickup tonight" } });
    expect(n.route).toBe("/posts/r_p1_zed");
    expect(n.text({}, 1)).toEqual({ title: "Zed reposted your post", body: "Look!" });
    expect(repostNotice({ repostId: "r", repost: { ...repost, body: "" }, original: { body: "Pickup tonight" } }).text({}, 1).body).toBe(
      "Pickup tonight",
    );
    // Followers of the reposter.
    expect(userPostNotice({ postId: "r_p1_zed", post: repost }).text({}, 1)).toEqual({
      title: "Zed reposted Sam's post",
      body: "Look!",
    });
  });

  it("offers to follow a new follower back", () => {
    const n = followerNotice({ followerId: "u9", name: "Riley", photoUrl: "https://x/p.png" });
    expect(n.category).toBe("social");
    expect(n.route).toBe("/players/u9");
    expect(n.collapseId).toBeUndefined();
    expect(n.text({}, 1).title).toBe("Riley started following you");
    expect(n.extra).toEqual({ followBack: { uid: "u9", name: "Riley", photoUrl: "https://x/p.png" } });
  });

  it("tells a private profile about requests, folded, and the asker when accepted", () => {
    const r = followRequestNotice({ requesterId: "u9", name: "Riley" });
    expect(r.route).toBe("/settings/follow-requests");
    expect(r.collapseId).toBe("followRequests");
    expect(r.text({}, 1).title).toBe("Riley wants to follow you");
    expect(r.text({}, 3).title).toBe("3 people want to follow you");
    const a = followAcceptedNotice({ ownerId: "u1", name: "Pat" });
    expect(a.route).toBe("/players/u1");
    expect(a.text({}, 1).title).toBe("Pat accepted your follow request");
  });

  it("previews event and repost posts", () => {
    expect(postPreview({ kind: "event", event: { title: "Showcase" } })).toBe("Showcase");
    expect(postPreview({ kind: "repost" })).toBe("A repost");
  });

  it("can be turned off", () => {
    expect(wants({ categories: { social: false } }, "social")).toBe(false);
    expect(wants({}, "social")).toBe(true);
  });
});

describe("comments", () => {
  it("tells the post's author, folding comments on one post", () => {
    const n = commentNotice({
      postId: "p1",
      post: { authorId: "sam", body: "Pickup tonight" },
      comment: { authorId: "zed", authorName: "Zed", body: "  I'm\n in! " },
    });
    expect(n.category).toBe("social");
    expect(n.route).toBe("/posts/p1");
    expect(n.collapseId).toBe("comments_p1");
    expect(n.text({}, 1)).toEqual({ title: "Zed commented on your post", body: "I'm in!" });
    expect(n.text({}, 3).title).toBe("3 new comments on your post");
  });

  it("tells whoever a reply answers, and never the replier or anyone twice", () => {
    const n = replyNotice({ postId: "p1", parentId: "c1", comment: { authorName: "Zed", body: "Same" } });
    expect(n.collapseId).toBe("replies_p1_c1");
    expect(n.route).toBe("/posts/p1");
    expect(n.text({}, 1)).toEqual({ title: "Zed replied to your comment", body: "Same" });
    expect(n.text({}, 2).title).toBe("2 new replies to your comment");
    expect(commentRecipients({ postAuthorId: "sam", commentAuthorId: "zed" })).toEqual({
      postAuthor: true,
      parentAuthor: false,
    });
    expect(commentRecipients({ postAuthorId: "sam", commentAuthorId: "zed", parentAuthorId: "ana" })).toEqual({
      postAuthor: true,
      parentAuthor: true,
    });
    // The post's author replying to a comment on their own post.
    expect(commentRecipients({ postAuthorId: "sam", commentAuthorId: "sam", parentAuthorId: "ana" })).toEqual({
      postAuthor: false,
      parentAuthor: true,
    });
    // Replying on your own comment's thread, or the parent is the post's author.
    expect(commentRecipients({ postAuthorId: "sam", commentAuthorId: "ana", parentAuthorId: "ana" }).parentAuthor).toBe(
      false,
    );
    expect(commentRecipients({ postAuthorId: "sam", commentAuthorId: "zed", parentAuthorId: "sam" })).toEqual({
      postAuthor: true,
      parentAuthor: false,
    });
  });

  it("tells a comment's author about likes, folded per comment", () => {
    const n = commentLikeNotice({ postId: "p1", commentId: "c1", comment: { body: "Huck it" }, likerName: "Ana" });
    expect(n.collapseId).toBe("commentLikes_p1_c1");
    expect(n.text({}, 1)).toEqual({ title: "Ana liked your comment", body: "Huck it" });
    expect(n.text({}, 4).title).toBe("4 new likes on your comment");
  });

  it("counts comments added and deleted, not edits", () => {
    expect(commentCountChange(false, true)).toBe(1);
    expect(commentCountChange(true, false)).toBe(-1);
    expect(commentCountChange(true, true)).toBe(0);
    expect(commentCountChange(false, false)).toBe(0);
  });
});
