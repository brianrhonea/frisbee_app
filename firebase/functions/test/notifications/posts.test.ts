import { describe, expect, it } from "vitest";

import {
  addItem,
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
  hasItem,
  itemsWithout,
  itemText,
  likeNotice,
  maxItems,
  newLikers,
  removedLikers,
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
    // One entry per follower, so unfollowing and following again isn't two.
    expect(n.collapseId).toBe("follower_u9");
    expect(n.item).toEqual({ key: "u9", name: "Riley", body: "" });
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

describe("folding by item", () => {
  const sam = { key: "sam", name: "Sam", body: "Good throws" };
  const ann = { key: "ann", name: "Ann", body: "Good throws" };

  it("counts distinct items: the same liker again moves to the end, not one more", () => {
    let items = addItem(undefined, sam);
    items = addItem(items, ann);
    items = addItem(items, sam);
    expect(items.map((i) => i.key)).toEqual(["ann", "sam"]);
    expect(hasItem(items, "sam")).toBe(true);
    expect(hasItem(items, "zed")).toBe(false);
    expect(itemText("likes", items)).toEqual({ title: "2 new likes on your post", body: "Good throws" });
  });

  it("re-words what's left when one is taken back, naming the newest", () => {
    const left = itemsWithout([sam, ann], "ann");
    expect(left).toEqual([sam]);
    expect(itemText("likes", left).title).toBe("Sam liked your post");
    expect(itemsWithout([sam], "sam")).toEqual([]);
  });

  it("tolerates entries from before items", () => {
    expect(itemsWithout(undefined, "x")).toEqual([]);
    expect(itemsWithout([{ nope: 1 }, null, sam], "x")).toEqual([sam]);
    expect(addItem([{ junk: true }], ann)).toEqual([ann]);
  });

  it("keeps at most maxItems", () => {
    let items = addItem(undefined, sam);
    for (let i = 0; i < maxItems + 5; i++) items = addItem(items, { key: `u${i}`, name: "X", body: "" });
    expect(items).toHaveLength(maxItems);
    expect(items.at(-1)?.key).toBe(`u${maxItems + 4}`);
  });

  it("words every kind for one and for several", () => {
    const one = [{ key: "c1", name: "Riley", body: "Nice" }];
    const two = [...one, { key: "c2", name: "Pat", body: "Agreed" }];
    expect(itemText("comments", one)).toEqual({ title: "Riley commented on your post", body: "Nice" });
    expect(itemText("comments", two)).toEqual({ title: "2 new comments on your post", body: "Agreed" });
    expect(itemText("replies", two).title).toBe("2 new replies to your comment");
    expect(itemText("commentLikes", one).title).toBe("Riley liked your comment");
    expect(itemText("followRequests", one).title).toBe("Riley wants to follow you");
    expect(itemText("followRequests", two).title).toBe("2 people want to follow you");
    expect(itemText("repost", one).title).toBe("Riley reposted your post");
    expect(itemText("follower", one).title).toBe("Riley started following you");
  });

  it("finds likes taken back", () => {
    expect(removedLikers({ likedBy: ["a", "b"] }, { likedBy: ["b"] })).toEqual(["a"]);
    expect(removedLikers({ likedBy: ["a"] }, { likedBy: ["a", "c"] })).toEqual([]);
    expect(removedLikers(undefined, { likedBy: ["a"] })).toEqual([]);
  });

  it("gives social notices their item and a check against undo races", () => {
    const like = likeNotice({ postId: "p1", post: { body: "Good throws" }, likerName: "Sam", likerId: "sam" });
    expect(like.itemKind).toBe("likes");
    expect(like.item).toEqual({ key: "sam", name: "Sam", body: "Good throws" });
    expect(like.check?.path).toBe("posts/p1");
    expect(like.check?.holds?.({ likedBy: ["sam"] })).toBe(true);
    expect(like.check?.holds?.({ likedBy: [] })).toBe(false);
    // Without the liker's id: the old count-every-event entry.
    expect(likeNotice({ postId: "p1", post: {}, likerName: "Sam" }).item).toBeUndefined();

    const comment = commentNotice({ postId: "p1", post: {}, comment: { authorName: "Riley", body: "Nice" }, commentId: "c1" });
    expect(comment.item).toEqual({ key: "c1", name: "Riley", body: "Nice" });
    expect(comment.check?.path).toBe("posts/p1/comments/c1");

    const reply = replyNotice({ postId: "p1", parentId: "c0", comment: { authorName: "Riley", body: "Yes" }, commentId: "c2" });
    expect(reply.item?.key).toBe("c2");
    expect(reply.itemKind).toBe("replies");

    const cl = commentLikeNotice({ postId: "p1", commentId: "c1", comment: { body: "Nice" }, likerName: "Sam", likerId: "sam" });
    expect(cl.itemKind).toBe("commentLikes");
    expect(cl.check?.holds?.({ likedBy: ["sam"] })).toBe(true);

    const request = followRequestNotice({ requesterId: "u9", name: "Riley", ownerId: "me" });
    expect(request.item?.key).toBe("u9");
    expect(request.check?.path).toBe("profiles/me/followRequests/u9");

    const repost = repostNotice({ repostId: "r_p1_zed", repost: { authorName: "Zed", body: "Look!" } });
    expect(repost.collapseId).toBe("repost_r_p1_zed");
    expect(repost.item).toEqual({ key: "r_p1_zed", name: "Zed", body: "Look!" });
    expect(repost.check?.path).toBe("posts/r_p1_zed");
  });
});
