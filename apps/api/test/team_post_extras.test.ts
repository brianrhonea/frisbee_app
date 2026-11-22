// Pinned team posts and comments on team posts (redesign F24), against
// FakeStore. API-only: firestore.rules lets no client write these.
import { teamPostPinsFullMessage, teamPostPinsMax } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
  const call = (method: "POST" | "PUT" | "PATCH" | "DELETE", url: string, body?: object, uid: string | null = "coach") =>
    app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
  return { store, users, call };
}

let s: ReturnType<typeof setup>;
const pin = (post: string) => `/v1/teams/t1/posts/${post}/pin`;
const comments = (post: string) => `/v1/teams/t1/posts/${post}/comments`;

beforeEach(() => {
  s = setup();
  s.users.records.set("coach", { name: "Casey Coach" });
  s.users.records.set("player", { name: "Pat Player" });
  s.users.records.set("admin", { name: "Ada Admin" });
  s.store.put("teams/t1", {
    name: "Haze",
    kind: "team",
    memberIds: ["coach", "player", "admin"],
    members: { coach: "coach", player: "player", admin: "player" },
    memberPerms: { admin: ["manageTeam"] },
  });
  for (let i = 0; i < 6; i++) s.store.put(`teams/t1/posts/p${i}`, { title: `Post ${i}`, body: "x", public: i % 2 === 0, authorId: "coach" });
});

describe("pins", () => {
  it("lets the team's admins pin and unpin, newest first", async () => {
    expect((await s.call("PUT", pin("p1"))).statusCode).toBe(204);
    expect((await s.call("PUT", pin("p2"), {}, "admin")).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/feed/pins")?.ids).toEqual(["p2", "p1"]);
    expect(s.store.doc("teams/t1/posts/p1")).toMatchObject({ pinnedAt: new Date(now), pinnedBy: "coach" });
    // Pinning again is a no-op.
    expect((await s.call("PUT", pin("p1"))).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/feed/pins")?.ids).toEqual(["p1", "p2"]);
    expect((await s.call("DELETE", pin("p1"), undefined, "admin")).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/feed/pins")?.ids).toEqual(["p2"]);
    expect(s.store.doc("teams/t1/posts/p1")).not.toHaveProperty("pinnedAt");
    expect(s.store.doc("teams/t1/posts/p1")).not.toHaveProperty("pinnedBy");
    // Unpinning what isn't pinned, or is gone, is a no-op.
    expect((await s.call("DELETE", pin("p3"))).statusCode).toBe(204);
    expect((await s.call("DELETE", pin("gone"))).statusCode).toBe(204);
  });

  it("refuses players, outsiders, visitors, and missing posts", async () => {
    expect((await s.call("PUT", pin("p1"), {}, "player")).statusCode).toBe(403);
    expect((await s.call("DELETE", pin("p1"), undefined, "player")).statusCode).toBe(403);
    expect((await s.call("PUT", pin("p1"), {}, "stranger")).statusCode).toBe(403);
    expect((await s.call("PUT", pin("p1"), {}, null)).statusCode).toBe(401);
    expect((await s.call("PUT", pin("gone"))).statusCode).toBe(404);
    expect((await s.call("PUT", "/v1/teams/nope/posts/p1/pin")).statusCode).toBe(404);
    expect(s.store.doc("teams/t1/posts/p1")).not.toHaveProperty("pinnedAt");
  });

  it(`holds ${teamPostPinsMax} pins, swaps one out on request, and forgets deleted posts' pins`, async () => {
    for (const id of ["p0", "p1", "p2"]) expect((await s.call("PUT", pin(id))).statusCode).toBe(204);
    const full = await s.call("PUT", pin("p3"));
    expect(full.statusCode).toBe(412);
    expect(full.json().error.message).toBe(teamPostPinsFullMessage);
    expect((await s.call("PUT", pin("p3"), { unpin: "p0" })).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/feed/pins")?.ids).toEqual(["p3", "p2", "p1"]);
    expect(s.store.doc("teams/t1/posts/p0")).not.toHaveProperty("pinnedAt");
    // A deleted post's pin frees its place.
    s.store.docs.delete("teams/t1/posts/p2");
    expect((await s.call("PUT", pin("p4"))).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/feed/pins")?.ids).toEqual(["p4", "p3", "p1"]);
  });

  it("keeps a pin when the post is edited", async () => {
    await s.call("PUT", pin("p1"));
    const edit = await s.call("PATCH", "/v1/teams/t1/posts/p1", { title: "New title", body: "Still pinned" });
    expect(edit.statusCode).toBe(200);
    expect(s.store.doc("teams/t1/posts/p1")).toMatchObject({ title: "New title", pinnedAt: new Date(now), pinnedBy: "coach" });
  });
});

describe("comments", () => {
  it("lets any member comment, trimmed, under their name", async () => {
    const res = await s.call("POST", comments("p1"), { body: "  See you there  " }, "player");
    expect(res.statusCode).toBe(201);
    const id = res.json().id;
    expect(s.store.doc(`teams/t1/posts/p1/comments/${id}`)).toEqual({
      authorId: "player",
      authorName: "Pat Player",
      body: "See you there",
      createdAt: new Date(now),
    });
    // The count is the function's (follows-teamPostCommentCount), not the API's.
    expect(s.store.doc("teams/t1/posts/p1")).not.toHaveProperty("commentCount");
  });

  it("refuses outsiders, visitors, empty or long comments and missing posts", async () => {
    expect((await s.call("POST", comments("p0"), { body: "hi" }, "stranger")).statusCode).toBe(403);
    expect((await s.call("POST", comments("p0"), { body: "hi" }, null)).statusCode).toBe(401);
    expect((await s.call("POST", comments("p0"), { body: "  " }, "player")).statusCode).toBe(400);
    expect((await s.call("POST", comments("p0"), { body: "x".repeat(1001) }, "player")).statusCode).toBe(400);
    expect((await s.call("POST", comments("gone"), { body: "hi" }, "player")).statusCode).toBe(404);
  });

  it("lets its author or an admin delete a comment, and nobody else", async () => {
    const mine = (await s.call("POST", comments("p1"), { body: "one" }, "player")).json().id;
    const other = (await s.call("POST", comments("p1"), { body: "two" }, "player")).json().id;
    const coachs = (await s.call("POST", comments("p1"), { body: "three" }, "coach")).json().id;
    expect((await s.call("DELETE", `${comments("p1")}/${coachs}`, undefined, "player")).statusCode).toBe(403);
    expect((await s.call("DELETE", `${comments("p1")}/${mine}`, undefined, "stranger")).statusCode).toBe(403);
    expect((await s.call("DELETE", `${comments("p1")}/${mine}`, undefined, "player")).statusCode).toBe(204);
    expect((await s.call("DELETE", `${comments("p1")}/${other}`, undefined, "admin")).statusCode).toBe(204);
    expect(s.store.doc(`teams/t1/posts/p1/comments/${mine}`)).toBeUndefined();
    expect(s.store.doc(`teams/t1/posts/p1/comments/${other}`)).toBeUndefined();
    expect(s.store.doc(`teams/t1/posts/p1/comments/${coachs}`)).toBeDefined();
    // Already gone: a no-op.
    expect((await s.call("DELETE", `${comments("p1")}/${mine}`, undefined, "player")).statusCode).toBe(204);
  });
});
