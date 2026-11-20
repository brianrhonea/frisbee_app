// Notes, clips and comments on team videos, and tagging a video to an
// event (redesign F4, F5, F6). API-only, so these are the only checks.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12);
let store: FakeStore;
type Res = { status: number; json: () => any };
let call: (method: "POST" | "PUT" | "DELETE", url: string, body?: object, uid?: string | null) => Promise<Res>;

beforeEach(() => {
  store = new FakeStore(() => now);
  const users = new FakeUsers();
  users.records.set("player", { name: "Pat Player" });
  users.records.set("coach", { name: "Coach Carter" });
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
  call = async (method, url, body, uid = "player") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
    return { status: res.statusCode, json: () => (res.body ? res.json() : undefined) };
  };
  store.put("teams/t1", {
    ownerId: "owner",
    memberIds: ["owner", "coach", "player", "other", "granted"],
    members: { owner: "owner", coach: "coach", player: "player", other: "player", granted: "player", ghost: "coach" },
    memberPerms: { granted: ["manageTeam"] },
  });
  store.put("teams/t1/videos/v1", { youtubeId: "dQw4w9WgXcQ", file: null, folderId: "", title: "Film", description: "", authorId: "coach", authorName: "Coach" });
  store.put("teams/t1/events/e1", { title: "Regionals", type: "tournament", startsAt: new Date(now - 86_400_000) });
});

const comments = "/v1/teams/t1/videos/v1/comments";
const add = (body: object, uid?: string | null) => call("POST", comments, body, uid);

describe("adding notes, clips and comments", () => {
  it("any member adds a comment, a note at a time, or a clip", async () => {
    const c = await add({ body: "  Great D  " });
    expect(c.status).toBe(201);
    expect(store.doc(`teams/t1/videos/v1/comments/${c.json().id}`)).toEqual({
      authorId: "player",
      authorName: "Pat Player",
      body: "Great D",
      createdAt: new Date(now),
    });
    const n = await add({ body: "Watch the mark", atMs: 83_000 });
    expect(store.doc(`teams/t1/videos/v1/comments/${n.json().id}`)).toMatchObject({ atMs: 83_000 });
    expect(store.doc(`teams/t1/videos/v1/comments/${n.json().id}`)).not.toHaveProperty("endMs");
    const clip = await add({ body: "Zone look", atMs: 10_000, endMs: 25_000 }, "coach");
    expect(store.doc(`teams/t1/videos/v1/comments/${clip.json().id}`)).toMatchObject({ authorId: "coach", atMs: 10_000, endMs: 25_000 });
  });

  it("signed in, members only, on a video that exists", async () => {
    expect((await add({ body: "x" }, null)).status).toBe(401);
    expect((await add({ body: "x" }, "stranger")).status).toBe(403);
    // A tier without membership (memberIds) isn't enough.
    expect((await add({ body: "x" }, "ghost")).status).toBe(403);
    expect((await call("POST", "/v1/teams/t1/videos/gone/comments", { body: "x" })).status).toBe(404);
    expect((await call("POST", "/v1/teams/nope/videos/v1/comments", { body: "x" })).status).toBe(404);
  });

  it("checks the body and times, and takes nothing else", async () => {
    expect((await add({ body: "   " })).status).toBe(400);
    expect((await add({ body: "x".repeat(1001) })).status).toBe(400);
    expect((await add({ body: "x", atMs: -1 })).status).toBe(400);
    expect((await add({ body: "x", endMs: 5000 })).status).toBe(400);
    expect((await add({ body: "x", atMs: 5000, endMs: 4000 })).status).toBe(400);
    expect((await add({ body: "x", authorId: "coach" })).status).toBe(400);
  });

  it("not while muted", async () => {
    store.put("limits/player", { mutedUntil: new Date(now + 60_000) });
    expect((await add({ body: "x" })).status).toBe(429);
  });
});

describe("deleting them", () => {
  beforeEach(() => {
    store.put("teams/t1/videos/v1/comments/mine", { authorId: "player", body: "a", createdAt: new Date(0) });
    store.put("teams/t1/videos/v1/comments/theirs", { authorId: "other", body: "b", createdAt: new Date(0) });
  });

  it("the author deletes their own", async () => {
    expect((await call("DELETE", `${comments}/mine`)).status).toBe(204);
    expect(store.doc("teams/t1/videos/v1/comments/mine")).toBeUndefined();
  });

  it("not someone else's, unless they manage the team", async () => {
    expect((await call("DELETE", `${comments}/theirs`)).status).toBe(403);
    expect(store.doc("teams/t1/videos/v1/comments/theirs")).toBeDefined();
    expect((await call("DELETE", `${comments}/theirs`, undefined, "granted")).status).toBe(204);
    expect((await call("DELETE", `${comments}/mine`, undefined, "coach")).status).toBe(204);
    expect(store.doc("teams/t1/videos/v1/comments/mine")).toBeUndefined();
  });

  it("outsiders can't, and one already gone is a no-op", async () => {
    expect((await call("DELETE", `${comments}/mine`, undefined, "stranger")).status).toBe(403);
    expect((await call("DELETE", `${comments}/nope`)).status).toBe(204);
  });

  it("they go with the video", async () => {
    expect((await call("DELETE", "/v1/teams/t1/videos/v1", undefined, "coach")).status).toBe(204);
    expect(store.doc("teams/t1/videos/v1")).toBeUndefined();
    expect(store.doc("teams/t1/videos/v1/comments/mine")).toBeUndefined();
    expect(store.doc("teams/t1/videos/v1/comments/theirs")).toBeUndefined();
  });
});

describe("tagging a video to an event", () => {
  const tag = (eventId: string | null, uid = "coach") => call("PUT", "/v1/teams/t1/videos/v1/event", { eventId }, uid);

  it("managers tag and untag", async () => {
    expect((await tag("e1")).status).toBe(204);
    expect(store.doc("teams/t1/videos/v1")?.eventId).toBe("e1");
    expect((await tag("e1", "granted")).status).toBe(204);
    expect((await tag(null, "owner")).status).toBe(204);
    expect(store.doc("teams/t1/videos/v1")).not.toHaveProperty("eventId");
    // Untagging an untagged video is a no-op.
    expect((await tag(null)).status).toBe(204);
  });

  it("only managers who are members", async () => {
    expect((await tag("e1", "player")).status).toBe(403);
    expect((await tag("e1", "ghost")).status).toBe(403);
    expect((await call("PUT", "/v1/teams/t1/videos/v1/event", { eventId: "e1" }, null)).status).toBe(401);
  });

  it("the event must be the team's, and the video must exist", async () => {
    expect((await tag("gone")).status).toBe(404);
    expect((await call("PUT", "/v1/teams/t1/videos/nope/event", { eventId: "e1" }, "coach")).status).toBe(404);
    expect((await call("PUT", "/v1/teams/t1/videos/v1/event", { eventId: "" }, "coach")).status).toBe(400);
    expect((await call("PUT", "/v1/teams/t1/videos/v1/event", { eventId: "e1", title: "x" }, "coach")).status).toBe(400);
  });

  it("a community tags only events for everyone", async () => {
    store.put("teams/t1", { ...store.doc("teams/t1"), kind: "organization" });
    store.put("teams/t1/events/e2", { title: "Coaches only", audience: ["role:coaches"] });
    store.put("teams/t1/events/e3", { title: "Open", audience: ["everyone"] });
    expect((await tag("e2")).status).toBe(412);
    expect((await tag("e3")).status).toBe(204);
  });

  it("isn't set when a video is added", async () => {
    const res = await call("POST", "/v1/teams/t1/videos", { youtubeId: "dQw4w9WgXcQ", title: "New" }, "coach");
    expect(res.status).toBe(201);
    expect(store.doc(`teams/t1/videos/${res.json().id}`)).not.toHaveProperty("eventId");
    expect((await call("POST", "/v1/teams/t1/videos", { youtubeId: "dQw4w9WgXcQ", title: "New", eventId: "e1" }, "coach")).status).toBe(400);
  });
});
