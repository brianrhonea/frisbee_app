// Writing posts and comments through the API, against FakeStore, following
// firestore.rules' posts and comments rules.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 12, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const media = new FakeMediaStorage();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users,
    teams: new FakeTeamRepository(),
    store,
    media,
    now: () => now,
  });
  const call = (method: "POST" | "PATCH" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "me") =>
    app.inject({
      method,
      url,
      ...(body && { payload: body }),
      headers: uid ? { authorization: `Bearer token:${uid}` } : {},
    });
  return { store, users, media, call };
}

/** A finished photo upload for post [postId]. */
function uploaded(s: ReturnType<typeof setup>, id: string, postId: string, uid = "me") {
  const path = `users/${uid}/posts/${postId}/${id}/${id}.jpg`;
  s.store.put(`uploads/${id}`, {
    uid,
    purpose: "post",
    itemId: postId,
    status: "ready",
    path,
    thumbPath: path.replace(".jpg", "_thumb.jpg"),
    contentType: "image/jpeg",
    actualSize: 1234,
  });
  s.media.files.set(path, { data: Buffer.from("x") });
  s.media.files.set(path.replace(".jpg", "_thumb.jpg"), { data: Buffer.from("x") });
  return path;
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.users.records.set("me", { name: "Mia Member", email: "mia@x.test", photoUrl: "https://img/m.jpg" });
});

describe("posts", () => {
  it("creates a text post as the caller, with the app's fields", async () => {
    const res = await s.call("POST", "/v1/posts", { body: "  First point  ", links: ["https://stall10.app"] });
    expect(res.statusCode).toBe(201);
    const { id } = res.json();
    expect(s.store.doc(`posts/${id}`)).toMatchObject({
      kind: "text",
      body: "First point",
      links: ["https://stall10.app"],
      images: [],
      workout: null,
      event: null,
      repostOf: null,
      authorId: "me",
      authorName: "Mia Member",
      authorPhotoUrl: "https://img/m.jpg",
    });
  });

  it("needs words or a photo, and refuses bad links", async () => {
    expect((await s.call("POST", "/v1/posts", { body: "   " })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/posts", { body: "hi", links: ["javascript:alert(1)"] })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/posts", { body: "hi" }, null)).statusCode).toBe(401);
  });

  it("creates a workout post, stored as the app stores one", async () => {
    const res = await s.call("POST", "/v1/posts", {
      body: "",
      workout: {
        activity: "gym",
        durationMinutes: 45,
        distanceKm: 3.14159,
        effort: 7,
        exercises: [{ name: " Squat ", sets: 3, reps: 5, weight: "100 kg" }, { name: "Plank" }],
      },
    });
    expect(res.statusCode).toBe(201);
    expect(s.store.doc(`posts/${res.json().id}`)).toMatchObject({
      kind: "workout",
      body: "",
      workout: {
        activity: "gym",
        durationMinutes: 45,
        distanceKm: 3.14,
        effort: 7,
        exercises: [{ name: "Squat", sets: 3, reps: 5, weight: "100 kg" }, { name: "Plank" }],
      },
    });
  });

  it("checks workouts as validWorkout does, and never changes one on an edit", async () => {
    const bad = [
      { activity: "swim", durationMinutes: 30 },
      { activity: "run", durationMinutes: 0 },
      { activity: "run", durationMinutes: 1441 },
      { activity: "run", durationMinutes: 1.5 },
      { activity: "run", durationMinutes: 30, distanceKm: 0 },
      { activity: "run", durationMinutes: 30, effort: 11 },
      { activity: "run", durationMinutes: 30, route: { path: "abc", splitsMi: [], splitsKm: [] } },
      { activity: "gym", durationMinutes: 30, exercises: [{ name: "" }] },
      { activity: "gym", durationMinutes: 30, exercises: [{ name: "Squat", sets: 101 }] },
      { activity: "gym", durationMinutes: 30, exercises: Array.from({ length: 21 }, () => ({ name: "Lunge" })) },
    ];
    for (const workout of bad) {
      expect((await s.call("POST", "/v1/posts", { workout })).statusCode, JSON.stringify(workout)).toBe(400);
    }
    const res = await s.call("POST", "/v1/posts", { workout: { activity: "run", durationMinutes: 20 } });
    const { id } = res.json();
    const edit = await s.call("PATCH", `/v1/posts/${id}`, {
      body: "Easy one",
      workout: { activity: "run", durationMinutes: 90 },
    });
    expect(edit.statusCode).toBe(400);
    expect((await s.call("PATCH", `/v1/posts/${id}`, { body: "Easy one" })).statusCode).toBe(200);
    expect(s.store.doc(`posts/${id}`)).toMatchObject({ kind: "workout", body: "Easy one", workout: { durationMinutes: 20 } });
  });

  it("adds only the caller's finished uploads for this post", async () => {
    const path = uploaded(s, "u1", "p1");
    const res = await s.call("POST", "/v1/posts", { id: "p1", uploadIds: ["u1"] });
    expect(res.statusCode).toBe(201);
    expect(s.store.doc("posts/p1")!.images).toEqual([{ path, name: "u1.jpg", contentType: "image/jpeg", size: 1234 }]);

    uploaded(s, "u2", "other");
    expect((await s.call("POST", "/v1/posts", { id: "p2", uploadIds: ["u2"] })).statusCode).toBe(400);
    uploaded(s, "u3", "p3", "pat");
    expect((await s.call("POST", "/v1/posts", { id: "p3", uploadIds: ["u3"] })).statusCode).toBe(400);
    s.store.put("uploads/u4", { uid: "me", purpose: "post", itemId: "p4", status: "processing" });
    expect((await s.call("POST", "/v1/posts", { id: "p4", uploadIds: ["u4"] })).statusCode).toBe(412);
  });

  it("refuses repost ids and existing posts", async () => {
    expect((await s.call("POST", "/v1/posts", { id: "r_x_me", body: "hi" })).statusCode).toBe(400);
    s.store.put("posts/taken", { kind: "text", authorId: "pat", body: "theirs" });
    expect((await s.call("POST", "/v1/posts", { id: "taken", body: "hi" })).statusCode).toBe(409);
    expect(s.store.doc("posts/taken")!.body).toBe("theirs");
  });

  it("refuses a muted member", async () => {
    s.store.put("limits/me", { mutedUntil: new Date(now + 5 * 60_000) });
    expect((await s.call("POST", "/v1/posts", { body: "hi" })).statusCode).toBe(429);
  });

  it("lets only the author edit, and deletes dropped photos", async () => {
    const a = uploaded(s, "a", "p1");
    const b = uploaded(s, "b", "p1");
    await s.call("POST", "/v1/posts", { id: "p1", body: "two photos", uploadIds: ["a", "b"] });
    expect((await s.call("PATCH", "/v1/posts/p1", { body: "hacked" }, "pat")).statusCode).toBe(403);

    const res = await s.call("PATCH", "/v1/posts/p1", { body: "one photo", keepImages: [a] });
    expect(res.statusCode).toBe(200);
    expect(s.store.doc("posts/p1")).toMatchObject({ body: "one photo", images: [{ path: a }] });
    expect(s.media.files.has(b)).toBe(false);
    expect(s.media.files.has(b.replace(".jpg", "_thumb.jpg"))).toBe(false);
    expect(s.media.files.has(a)).toBe(true);
  });

  it("keeps a workout post's workout and only changes a repost's note", async () => {
    s.store.put("posts/w", { kind: "workout", authorId: "me", body: "run", workout: { activity: "run" }, images: [] });
    await s.call("PATCH", "/v1/posts/w", { body: "" });
    expect(s.store.doc("posts/w")).toMatchObject({ kind: "workout", body: "", workout: { activity: "run" } });

    s.store.put("posts/r_o_me", { kind: "repost", authorId: "me", body: "", repostOf: { postId: "o" } });
    expect((await s.call("PATCH", "/v1/posts/r_o_me", { body: "so good" })).statusCode).toBe(200);
    expect(s.store.doc("posts/r_o_me")!.body).toBe("so good");
    expect((await s.call("PATCH", "/v1/posts/r_o_me", { body: "x", links: ["https://a.b"] })).statusCode).toBe(400);
  });

  it("deletes the author's post with its photos", async () => {
    const a = uploaded(s, "a", "p1");
    await s.call("POST", "/v1/posts", { id: "p1", uploadIds: ["a"] });
    expect((await s.call("DELETE", "/v1/posts/p1", undefined, "pat")).statusCode).toBe(403);
    expect((await s.call("DELETE", "/v1/posts/p1")).statusCode).toBe(204);
    expect(s.store.doc("posts/p1")).toBeUndefined();
    expect(s.media.files.has(a)).toBe(false);
    // Again is fine.
    expect((await s.call("DELETE", "/v1/posts/p1")).statusCode).toBe(204);
  });

  it("deleting a repost takes the caller off the original's repostedBy", async () => {
    s.store.put("posts/o", { kind: "text", authorId: "pat", body: "orig", repostedBy: ["me", "sam"] });
    s.store.put("posts/r_o_me", { kind: "repost", authorId: "me", body: "", repostOf: { postId: "o", authorId: "pat" } });
    await s.call("DELETE", "/v1/posts/r_o_me");
    expect(s.store.doc("posts/r_o_me")).toBeUndefined();
    expect(s.store.doc("posts/o")!.repostedBy).toEqual(["sam"]);
  });
});

describe("comments", () => {
  beforeEach(() => {
    s.store.put("posts/p", { kind: "text", authorId: "pat", body: "post" });
  });

  it("comments and replies one level deep", async () => {
    const top = (await s.call("POST", "/v1/posts/p/comments", { body: " Nice " })).json().id;
    expect(s.store.doc(`posts/p/comments/${top}`)).toMatchObject({ body: "Nice", authorId: "me", authorName: "Mia Member" });
    expect(s.store.doc(`posts/p/comments/${top}`)!.parentId).toBeUndefined();

    s.users.records.set("sam", { name: "Sam" });
    const reply = (await s.call("POST", "/v1/posts/p/comments", { body: "Thanks", replyTo: top }, "sam")).json().id;
    expect(s.store.doc(`posts/p/comments/${reply}`)).toMatchObject({ parentId: top });
    expect(s.store.doc(`posts/p/comments/${reply}`)!.replyToName).toBeUndefined();

    // Replying to a reply answers the top-level comment and says whose.
    const again = (await s.call("POST", "/v1/posts/p/comments", { body: "Ha", replyTo: reply })).json().id;
    expect(s.store.doc(`posts/p/comments/${again}`)).toMatchObject({ parentId: top, replyToName: "Sam" });
  });

  it("refuses empty comments, missing posts and reposts", async () => {
    expect((await s.call("POST", "/v1/posts/p/comments", { body: "  " })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/posts/gone/comments", { body: "hi" })).statusCode).toBe(404);
    s.store.put("posts/r_p_sam", { kind: "repost", authorId: "sam", repostOf: { postId: "p" } });
    expect((await s.call("POST", "/v1/posts/r_p_sam/comments", { body: "hi" })).statusCode).toBe(412);
    expect((await s.call("POST", "/v1/posts/p/comments", { body: "hi", replyTo: "nope" })).statusCode).toBe(404);
  });

  it("lets its author edit, and its author or the post's author delete", async () => {
    s.store.put("posts/p/comments/c", { body: "mine", authorId: "me" });
    expect((await s.call("PATCH", "/v1/posts/p/comments/c", { body: "x" }, "sam")).statusCode).toBe(403);
    expect((await s.call("PATCH", "/v1/posts/p/comments/c", { body: "edited" })).statusCode).toBe(204);
    expect(s.store.doc("posts/p/comments/c")).toMatchObject({ body: "edited", editedAt: new Date(now) });

    expect((await s.call("DELETE", "/v1/posts/p/comments/c", undefined, "sam")).statusCode).toBe(403);
    expect((await s.call("DELETE", "/v1/posts/p/comments/c", undefined, "pat")).statusCode).toBe(204);
    expect(s.store.doc("posts/p/comments/c")).toBeUndefined();
  });

  it("likes and unlikes as the caller only", async () => {
    s.store.put("posts/p/comments/c", { body: "x", authorId: "sam", likedBy: ["pat"] });
    let res = await s.call("PUT", "/v1/posts/p/comments/c/like");
    expect(res.json()).toEqual({ liked: true, likeCount: 2 });
    res = await s.call("PUT", "/v1/posts/p/comments/c/like");
    expect(res.json()).toEqual({ liked: true, likeCount: 2 });
    res = await s.call("DELETE", "/v1/posts/p/comments/c/like");
    expect(res.json()).toEqual({ liked: false, likeCount: 1 });
    expect(s.store.doc("posts/p/comments/c")!.likedBy).toEqual(["pat"]);
  });
});
