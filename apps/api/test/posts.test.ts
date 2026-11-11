// Likes and reposts through the API, against FakeStore, following
// firestore.rules' posts rule (like/repost update, repost create) and the
// app's PostActions (a repost's likes and reposts go to its original).
import { postReactionMax, repostId } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 11, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, now: () => now });
  const call = (method: "GET" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "me") =>
    app.inject({
      method,
      url,
      ...(body && { payload: body }),
      headers: uid ? { authorization: `Bearer token:${uid}` } : {},
    });
  return { store, users, call };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.users.records.set("me", { name: "Mia Member", email: "mia@x.test", photoUrl: "https://img/m.jpg" });
  s.store.put("posts/orig", { kind: "text", authorId: "pat", authorName: "Pat Public", body: "Hello", likedBy: ["x"], repostedBy: [] });
  s.store.put("posts/mine", { kind: "text", authorId: "me", authorName: "Mia Member", body: "Mine" });
  // Someone else's repost of orig.
  s.store.put("posts/r_orig_sam", {
    kind: "repost",
    authorId: "sam",
    body: "",
    repostOf: { postId: "orig", authorId: "pat", authorName: "Pat Public" },
  });
});

describe("likes", () => {
  it("adds and removes only the caller", async () => {
    let res = await s.call("PUT", "/v1/posts/orig/like");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ liked: true, likeCount: 2 });
    expect(s.store.doc("posts/orig")!.likedBy).toEqual(["x", "me"]);
    res = await s.call("DELETE", "/v1/posts/orig/like");
    expect(res.json()).toEqual({ liked: false, likeCount: 1 });
    expect(s.store.doc("posts/orig")!.likedBy).toEqual(["x"]);
  });

  it("is idempotent: liking twice lists them once", async () => {
    await s.call("PUT", "/v1/posts/orig/like");
    const res = await s.call("PUT", "/v1/posts/orig/like");
    expect(res.json()).toEqual({ liked: true, likeCount: 2 });
    expect(s.store.doc("posts/orig")!.likedBy).toEqual(["x", "me"]);
  });

  it("liking a repost likes its original", async () => {
    await s.call("PUT", "/v1/posts/r_orig_sam/like");
    expect(s.store.doc("posts/orig")!.likedBy).toEqual(["x", "me"]);
    expect(s.store.doc("posts/r_orig_sam")!.likedBy).toBeUndefined();
  });

  it("lets people like their own post (the rule does)", async () => {
    expect((await s.call("PUT", "/v1/posts/mine/like")).json()).toEqual({ liked: true, likeCount: 1 });
  });

  it("stops at the rule's cap", async () => {
    s.store.put("posts/busy", { authorId: "pat", likedBy: Array.from({ length: postReactionMax }, (_, i) => `u${i}`) });
    expect((await s.call("PUT", "/v1/posts/busy/like")).statusCode).toBe(412);
  });

  it("needs a signed-in caller, an existing post and a valid id", async () => {
    expect((await s.call("PUT", "/v1/posts/orig/like", undefined, null)).statusCode).toBe(401);
    expect((await s.call("PUT", "/v1/posts/nope/like")).statusCode).toBe(404);
    expect((await s.call("PUT", "/v1/posts/__x__/like")).statusCode).toBe(400);
  });
});

describe("reposts", () => {
  const mine = `posts/${repostId("orig", "me")}`;

  it("writes the repost the app writes, with the original's repostedBy, together", async () => {
    const res = await s.call("PUT", "/v1/posts/orig/repost", { note: "  Look at this " });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ reposted: true, repostCount: 1 });
    expect(s.store.doc(mine)).toEqual({
      kind: "repost",
      body: "Look at this",
      links: [],
      images: [],
      workout: null,
      event: null,
      repostOf: { postId: "orig", authorId: "pat", authorName: "Pat Public" },
      tournamentKey: null,
      tournamentName: null,
      authorId: "me",
      authorName: "Mia Member",
      authorPhotoUrl: "https://img/m.jpg",
      createdAt: new Date(now),
      updatedAt: new Date(now),
    });
    expect(s.store.doc("posts/orig")!.repostedBy).toEqual(["me"]);
  });

  it("reposting a repost reposts its original", async () => {
    await s.call("PUT", "/v1/posts/r_orig_sam/repost", {});
    expect(s.store.doc(mine)!.repostOf).toEqual({ postId: "orig", authorId: "pat", authorName: "Pat Public" });
    expect(s.store.doc("posts/orig")!.repostedBy).toEqual(["me"]);
  });

  it("again is a no-op", async () => {
    await s.call("PUT", "/v1/posts/orig/repost", { note: "first" });
    const res = await s.call("PUT", "/v1/posts/orig/repost", { note: "second" });
    expect(res.json()).toEqual({ reposted: true, repostCount: 1 });
    expect(s.store.doc(mine)!.body).toBe("first");
  });

  it("refuses the caller's own post", async () => {
    const res = await s.call("PUT", "/v1/posts/mine/repost", {});
    expect(res.statusCode).toBe(403);
    expect(s.store.doc(`posts/${repostId("mine", "me")}`)).toBeUndefined();
  });

  it("refuses a muted caller (notMuted)", async () => {
    s.store.put("limits/me", { mutedUntil: new Date(now + 5 * 60_000) });
    const res = await s.call("PUT", "/v1/posts/orig/repost", {});
    expect(res.statusCode).toBe(429);
    expect(s.store.doc(mine)).toBeUndefined();
  });

  it("checks the note", async () => {
    expect((await s.call("PUT", "/v1/posts/orig/repost", { note: "x".repeat(5001) })).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/posts/orig/repost", { note: 5 })).statusCode).toBe(400);
  });

  it("never shows an email as the reposter's name", async () => {
    s.users.records.set("me", { email: "mia@x.test" });
    s.store.put("profiles/me", { username: "mia" });
    await s.call("PUT", "/v1/posts/orig/repost", {});
    expect(s.store.doc(mine)!.authorName).toBe("@mia");
  });

  it("undo deletes the repost and the caller's repostedBy entry, from the original or the repost", async () => {
    await s.call("PUT", "/v1/posts/orig/repost", {});
    let res = await s.call("DELETE", "/v1/posts/orig/repost");
    expect(res.json()).toEqual({ reposted: false, repostCount: 0 });
    expect(s.store.doc(mine)).toBeUndefined();
    expect(s.store.doc("posts/orig")!.repostedBy).toEqual([]);

    await s.call("PUT", "/v1/posts/orig/repost", {});
    res = await s.call("DELETE", `/v1/posts/${repostId("orig", "me")}/repost`);
    expect(s.store.doc(mine)).toBeUndefined();
    expect(s.store.doc("posts/orig")!.repostedBy).toEqual([]);
  });

  it("undo still removes the repost once the original is gone", async () => {
    await s.call("PUT", "/v1/posts/orig/repost", {});
    s.store.docs.delete("posts/orig");
    const res = await s.call("DELETE", `/v1/posts/${repostId("orig", "me")}/repost`);
    expect(res.statusCode).toBe(200);
    expect(s.store.doc(mine)).toBeUndefined();
  });

  it("undo never deletes someone else's repost", async () => {
    await s.call("DELETE", "/v1/posts/r_orig_sam/repost");
    expect(s.store.doc("posts/r_orig_sam")).toBeDefined();
  });
});

describe("state", () => {
  it("gives the caller's likes and reposts, a repost's from its original", async () => {
    await s.call("PUT", "/v1/posts/orig/like");
    const res = await s.call("GET", "/v1/posts/state?ids=orig,r_orig_sam,mine,nope");
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toBe("private, no-store");
    const both = { liked: true, reposted: false, canRepost: true, likeCount: 2, repostCount: 0 };
    expect(res.json()).toEqual({
      orig: both,
      r_orig_sam: both,
      mine: { liked: false, reposted: false, canRepost: false, likeCount: 0, repostCount: 0 },
    });
  });

  it("asks about at most 50", async () => {
    const ids = Array.from({ length: 51 }, (_, i) => `p${i}`).join(",");
    expect((await s.call("GET", `/v1/posts/state?ids=${ids}`)).statusCode).toBe(400);
  });

  it("needs a signed-in caller", async () => {
    expect((await s.call("GET", "/v1/posts/state?ids=orig", undefined, null)).statusCode).toBe(401);
  });
});
