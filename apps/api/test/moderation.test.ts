// Reports, blocks and the review queues through the API, against FakeStore.
// Blocks mirror firestore.rules' blockedWith(): one record for each person.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { reportId } from "../src/moderation/service.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 20, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, now: () => now });
  const call = (method: "GET" | "POST" | "PUT" | "DELETE", url: string, body?: object, uid = "me", kind = "token") =>
    app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer ${kind}:${uid}` } });
  return { store, users, call };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.store.put("profiles/me", { name: "Mia Member", username: "mia" });
  s.store.put("profiles/pat", { name: "Pat Public", username: "pat", photoUrl: "https://img/p.jpg" });
  s.store.put("posts/p1", { authorId: "pat", authorName: "Pat Public", kind: "text", body: "Buy followers here", images: [{ url: "https://img/x.jpg", path: "users/pat/posts/p1/a.jpg" }] });
  s.store.put("posts/p1/comments/c1", { authorId: "pat", authorName: "Pat Public", body: "rude comment" });
  s.store.put("teams/t1", {
    name: "Northside Flyers",
    memberIds: ["own", "me", "pat", "cap"],
    members: { own: "owner", me: "player", pat: "player", cap: "captain" },
  });
  s.store.put("teams/t1/chats/general", { name: "General", readUsers: ["me", "pat", "cap"], writeUsers: ["me", "pat", "cap"] });
  s.store.put("teams/t1/chats/general/messages/m1", { authorId: "pat", authorName: "Pat Public", text: "mean message", attachments: [] });
});

describe("reports", () => {
  it("snapshots a post, keeps one report per person, and lets staff see it", async () => {
    let res = await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "p1" }, reason: "spam", details: "Bot" });
    expect(res.statusCode).toBe(201);
    const id = res.json().id;
    expect(id).toBe(reportId("me", { kind: "post", postId: "p1" }));
    expect(s.store.doc(`reports/${id}`)).toMatchObject({
      reporterId: "me",
      authorId: "pat",
      reason: "spam",
      details: "Bot",
      status: "open",
      snapshot: { text: "Buy followers here", images: ["https://img/x.jpg"] },
      teamId: null,
    });
    res = await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "p1" }, reason: "hate" });
    expect(res.json().id).toBe(id);
    expect([...s.store.docs.keys()].filter((k) => k.startsWith("reports/"))).toHaveLength(1);

    expect((await s.call("GET", "/v1/staff/reports")).statusCode).toBe(403);
    const queue = (await s.call("GET", "/v1/staff/reports", undefined, "boss", "staff")).json();
    expect(queue).toHaveLength(1);
    expect(queue[0]).toMatchObject({ id, reason: "hate", reporterId: "me", authorName: "Pat Public", authorSuspended: false });
  });

  it("refuses your own content, yourself, and what isn't there", async () => {
    s.store.put("posts/mine", { authorId: "me", body: "x" });
    expect((await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "mine" }, reason: "spam" })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/reports", { target: { kind: "user", uid: "me" }, reason: "spam" })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "nope" }, reason: "spam" })).statusCode).toBe(404);
    expect((await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "p1" }, reason: "meh" })).statusCode).toBe(400);
  });

  it("doesn't let outsiders report a team's private chat", async () => {
    const target = { kind: "teamMessage", teamId: "t1", roomId: "general", messageId: "m1" };
    expect((await s.call("POST", "/v1/reports", { target, reason: "harassment" }, "stranger")).statusCode).toBe(404);
  });

  it("reports and blocks in one go", async () => {
    const res = await s.call("POST", "/v1/reports", { target: { kind: "comment", postId: "p1", commentId: "c1" }, reason: "harassment", block: true });
    expect(res.json().blocked).toBe(true);
    expect(s.store.doc("users/me/blocks/pat")).toMatchObject({ mine: true, name: "Pat Public" });
    expect(s.store.doc("users/pat/blocks/me")).toMatchObject({ mine: false });
  });

  it("goes to the team's admins, without the reporter's name, and they remove it", async () => {
    const target = { kind: "teamMessage", teamId: "t1", roomId: "general", messageId: "m1" };
    await s.call("POST", "/v1/reports", { target, reason: "harassment" });
    await s.call("POST", "/v1/reports", { target, reason: "hate" }, "cap");

    expect((await s.call("GET", "/v1/teams/t1/reports")).statusCode).toBe(403);
    const list = (await s.call("GET", "/v1/teams/t1/reports", undefined, "own")).json();
    expect(list).toHaveLength(2);
    expect(list[0]).toMatchObject({ teamName: "Northside Flyers", reporterId: null, reporterName: null, snapshot: { text: "mean message" } });

    const res = await s.call("POST", `/v1/teams/t1/reports/${list[0].id}`, { action: "remove" }, "own");
    expect(res.statusCode).toBe(204);
    expect(s.store.doc("teams/t1/chats/general/messages/m1")).toBeUndefined();
    // Both reports on it close together.
    expect((await s.call("GET", "/v1/teams/t1/reports", undefined, "own")).json()).toHaveLength(0);
    expect(s.store.doc(`reports/${list[1].id}`)).toMatchObject({ status: "removed", resolvedBy: "own" });
  });

  it("a team admin only handles their own team's reports", async () => {
    await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "p1" }, reason: "spam" });
    const id = reportId("me", { kind: "post", postId: "p1" });
    expect((await s.call("POST", `/v1/teams/t1/reports/${id}`, { action: "remove" }, "own")).statusCode).toBe(404);
    expect(s.store.doc("posts/p1")).toBeDefined();
  });

  it("staff remove a post, warn, suspend and lift it", async () => {
    await s.call("POST", "/v1/reports", { target: { kind: "post", postId: "p1" }, reason: "spam" });
    const id = reportId("me", { kind: "post", postId: "p1" });
    const staff = (body: object) => s.call("POST", `/v1/staff/reports/${id}`, body, "boss", "staff");

    expect((await s.call("POST", `/v1/staff/reports/${id}`, { action: "remove" })).statusCode).toBe(403);
    expect((await staff({ action: "warn" })).statusCode).toBe(204);
    expect(s.store.doc(`users/pat/notifications/warning_${id}`)).toMatchObject({ title: "A warning from Stall 10", read: false });

    expect((await staff({ action: "suspend", note: "Spam bot" })).statusCode).toBe(204);
    expect(s.store.doc("limits/pat")).toMatchObject({ suspended: true, suspendedBy: "boss" });
    expect(s.users.disabled.has("pat")).toBe(true);
    // A suspended account can't post.
    const post = await s.call("POST", "/v1/posts/p1/comments", { body: "still here" }, "pat");
    expect(post.statusCode).toBe(403);
    expect(post.json().error.message).toContain("suspended");

    expect((await staff({ action: "remove" })).statusCode).toBe(204);
    expect(s.store.doc("posts/p1")).toBeUndefined();
    expect(s.store.doc(`reports/${id}`)).toMatchObject({ status: "removed", resolvedBy: "boss" });

    await staff({ action: "unsuspend" });
    expect(s.store.doc("limits/pat")).toMatchObject({ suspended: false });
    expect(s.users.disabled.has("pat")).toBe(false);
  });

  it("staff dismiss a report", async () => {
    await s.call("POST", "/v1/reports", { target: { kind: "user", uid: "pat" }, reason: "impersonation" });
    const id = reportId("me", { kind: "user", uid: "pat" });
    expect((await s.call("POST", `/v1/staff/reports/${id}`, { action: "remove" }, "boss", "staff")).statusCode).toBe(400);
    await s.call("POST", `/v1/staff/reports/${id}`, { action: "dismiss" }, "boss", "staff");
    expect(s.store.doc(`reports/${id}`)).toMatchObject({ status: "dismissed" });
    expect((await s.call("GET", "/v1/staff/reports", undefined, "boss", "staff")).json()).toHaveLength(0);
  });

  it("says who is staff", async () => {
    expect((await s.call("GET", "/v1/me/moderation")).json()).toEqual({ staff: false });
    expect((await s.call("GET", "/v1/me/moderation", undefined, "boss", "staff")).json()).toEqual({ staff: true });
  });
});

describe("blocks", () => {
  it("removes follows and requests both ways, and lists only your own blocks", async () => {
    s.store.put("users/me/follows/user_pat", { type: "user", targetId: "pat" });
    s.store.put("users/pat/follows/user_me", { type: "user", targetId: "me" });
    s.store.put("profiles/me/followRequests/pat", { name: "Pat" });
    expect((await s.call("PUT", "/v1/me/blocks/pat")).statusCode).toBe(204);
    expect(s.store.doc("users/me/follows/user_pat")).toBeUndefined();
    expect(s.store.doc("users/pat/follows/user_me")).toBeUndefined();
    expect(s.store.doc("profiles/me/followRequests/pat")).toBeUndefined();

    const mine = (await s.call("GET", "/v1/me/blocks")).json();
    expect(mine.blocked).toEqual([expect.objectContaining({ uid: "pat", name: "Pat Public", username: "pat" })]);
    expect(mine.hidden).toEqual(["pat"]);
    const theirs = (await s.call("GET", "/v1/me/blocks", undefined, "pat")).json();
    expect(theirs).toEqual({ blocked: [], hidden: ["me"] });
  });

  it("stops following, messaging, commenting and liking between them", async () => {
    await s.call("PUT", "/v1/me/blocks/pat");
    expect((await s.call("PUT", "/v1/follows", { type: "user", targetId: "me" }, "pat")).statusCode).toBe(403);
    expect((await s.call("PUT", "/v1/follows", { type: "user", targetId: "pat" })).statusCode).toBe(403);
    expect((await s.call("POST", "/v1/conversations", { with: "me" }, "pat")).statusCode).toBe(403);
    expect((await s.call("POST", "/v1/posts/p1/comments", { body: "hi" })).statusCode).toBe(403);
    expect((await s.call("PUT", "/v1/posts/p1/like")).statusCode).toBe(403);
  });

  it("refuses messages in a direct conversation they already had", async () => {
    s.store.put("conversations/me_pat", { participants: ["me", "pat"], names: { me: "Mia", pat: "Pat" }, status: "accepted" });
    await s.call("PUT", "/v1/me/blocks/pat");
    const res = await s.call("POST", "/v1/conversations/me_pat/messages", { text: "hello?" }, "pat");
    expect(res.statusCode).toBe(403);
  });

  it("unblocks, but stays blocked while the other person blocks too", async () => {
    await s.call("PUT", "/v1/me/blocks/pat");
    await s.call("PUT", "/v1/me/blocks/me", undefined, "pat");
    await s.call("DELETE", "/v1/me/blocks/pat");
    expect(s.store.doc("users/me/blocks/pat")).toMatchObject({ mine: false });
    expect(s.store.doc("users/pat/blocks/me")).toMatchObject({ mine: true });
    await s.call("DELETE", "/v1/me/blocks/me", undefined, "pat");
    expect(s.store.doc("users/me/blocks/pat")).toBeUndefined();
    expect(s.store.doc("users/pat/blocks/me")).toBeUndefined();
  });

  it("can't block yourself or nobody", async () => {
    expect((await s.call("PUT", "/v1/me/blocks/me")).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/me/blocks/ghost")).statusCode).toBe(404);
  });
});
