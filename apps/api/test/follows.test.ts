// Follows, follow requests and notifications through the API, against
// FakeStore, following firestore.rules' follows, followRequests and
// notifications rules.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 12, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, now: () => now });
  const call = (method: "POST" | "PATCH" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "me") =>
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
  s.users.records.set("me", { name: "Mia Member", photoUrl: "https://img/m.jpg" });
  s.store.put("profiles/me", { name: "Mia Member", username: "mia" });
  s.store.put("profiles/pat", { name: "Pat Public", photoUrl: "https://img/p.jpg" });
  s.store.put("profiles/quinn", { name: "Quinn Quiet", private: true });
  s.store.put("teams/t1", { name: "Northside Flyers" });
});

describe("follows", () => {
  it("follows a player with their name and photo, once", async () => {
    let res = await s.call("PUT", "/v1/follows", { type: "user", targetId: "pat" });
    expect(res.json()).toEqual({ key: "user_pat", status: "following" });
    expect(s.store.doc("users/me/follows/user_pat")).toMatchObject({
      key: "user_pat",
      type: "user",
      targetId: "pat",
      name: "Pat Public",
      photoUrl: "https://img/p.jpg",
      notify: false,
      createdAt: new Date(now),
    });
    res = await s.call("PUT", "/v1/follows", { type: "user", targetId: "pat", notify: true });
    expect(res.json().status).toBe("following");
  });

  it("follows teams and tournaments by their names", async () => {
    await s.call("PUT", "/v1/follows", { type: "team", targetId: "t1", notify: true });
    expect(s.store.doc("users/me/follows/team_t1")).toMatchObject({ name: "Northside Flyers", notify: true });

    s.store.put("tournaments/hat", { name: "Winter Hat", hostId: "t1" });
    const res = await s.call("PUT", "/v1/follows", { type: "tournament", targetId: "hat", groupId: "t1" });
    expect(res.json().key).toBe("tournament_t1_hat");
    expect(s.store.doc("users/me/follows/tournament_t1_hat")).toMatchObject({
      targetId: "t1_hat",
      groupId: "t1",
      name: "Winter Hat",
    });
    // A tournament hosted by someone else isn't this group's.
    expect((await s.call("PUT", "/v1/follows", { type: "tournament", targetId: "hat", groupId: "t9" })).statusCode).toBe(404);
  });

  it("refuses yourself, missing targets and muted members", async () => {
    expect((await s.call("PUT", "/v1/follows", { type: "user", targetId: "me" })).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/follows", { type: "team", targetId: "nope" })).statusCode).toBe(404);
    s.store.put("limits/me", { mutedUntil: new Date(now + 60_000) });
    expect((await s.call("PUT", "/v1/follows", { type: "user", targetId: "pat" })).statusCode).toBe(429);
  });

  it("asks a private player first, and they accept or decline", async () => {
    const res = await s.call("PUT", "/v1/follows", { type: "user", targetId: "quinn" });
    expect(res.json()).toEqual({ key: "user_quinn", status: "requested" });
    expect(s.store.doc("users/me/follows/user_quinn")).toBeUndefined();
    expect(s.store.doc("profiles/quinn/followRequests/me")).toMatchObject({
      name: "Mia Member",
      username: "mia",
      photoUrl: "https://img/m.jpg",
    });

    // Only Quinn can accept.
    expect((await s.call("POST", "/v1/me/follow-requests/me/accept", undefined, "pat")).statusCode).toBe(404);
    expect((await s.call("POST", "/v1/me/follow-requests/me/accept", undefined, "quinn")).statusCode).toBe(204);
    expect(s.store.doc("users/me/follows/user_quinn")).toMatchObject({ approved: true, name: "Quinn Quiet" });
    expect(s.store.doc("profiles/quinn/followRequests/me")).toBeUndefined();

    // Quinn removes them again.
    await s.call("DELETE", "/v1/me/followers/me", undefined, "quinn");
    expect(s.store.doc("users/me/follows/user_quinn")).toBeUndefined();
  });

  it("cancels and declines requests", async () => {
    await s.call("PUT", "/v1/follows", { type: "user", targetId: "quinn" });
    await s.call("DELETE", "/v1/follows/requests/quinn");
    expect(s.store.doc("profiles/quinn/followRequests/me")).toBeUndefined();
    await s.call("PUT", "/v1/follows", { type: "user", targetId: "quinn" });
    await s.call("DELETE", "/v1/me/follow-requests/me", undefined, "quinn");
    expect(s.store.doc("profiles/quinn/followRequests/me")).toBeUndefined();
  });

  it("unfollows and switches notifications", async () => {
    await s.call("PUT", "/v1/follows", { type: "team", targetId: "t1" });
    expect((await s.call("PATCH", "/v1/follows/team_t1", { notify: true })).statusCode).toBe(204);
    expect(s.store.doc("users/me/follows/team_t1")!.notify).toBe(true);
    expect((await s.call("PATCH", "/v1/follows/team_x", { notify: true })).statusCode).toBe(404);
    await s.call("DELETE", "/v1/follows/team_t1");
    expect(s.store.doc("users/me/follows/team_t1")).toBeUndefined();
  });
});

describe("notifications", () => {
  it("marks the caller's own notifications read and clears them", async () => {
    s.store.put("users/me/notifications/a", { title: "A", read: false });
    s.store.put("users/me/notifications/b", { title: "B", read: false });
    s.store.put("users/pat/notifications/a", { title: "Pat's", read: false });
    expect((await s.call("POST", "/v1/me/notifications/read", { ids: ["a", "b", "gone"] })).statusCode).toBe(204);
    expect(s.store.doc("users/me/notifications/a")!.read).toBe(true);
    expect(s.store.doc("users/me/notifications/b")!.read).toBe(true);
    expect(s.store.doc("users/pat/notifications/a")!.read).toBe(false);

    await s.call("POST", "/v1/me/notifications/delete", { ids: ["a"] });
    expect(s.store.doc("users/me/notifications/a")).toBeUndefined();
    expect(s.store.doc("users/pat/notifications/a")).toBeDefined();
    expect((await s.call("POST", "/v1/me/notifications/read", { ids: [] })).statusCode).toBe(400);
  });
});
