// The caller's name, pictures and notification settings, against fakes.
import { termsVersion } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const media = new FakeMediaStorage();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media, now: () => now });
  const call = (method: "GET" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "amy") =>
    app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
  return { store, users, media, call };
}

let s: ReturnType<typeof setup>;
const avatar = (id: string, uid = "amy", extra: object = {}) =>
  s.store.put(`uploads/${id}`, { uid, purpose: "avatar", status: "ready", path: `users/${uid}/profile/${id}.jpg`, contentType: "image/jpeg", ...extra });

beforeEach(() => {
  s = setup();
  s.users.records.set("amy", { name: "Amy", email: "amy@x.test" });
  s.store.put("profiles/amy", { name: "Amy", username: "amyk", private: true, bio: "hidden" });
});

describe("name and pictures", () => {
  it("renames on the account, users doc and profile, with fresh keywords", async () => {
    const res = await s.call("PUT", "/v1/me/identity", { name: "  Amy Kay " });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ name: "Amy Kay", photoUrl: null, headerUrl: null });
    expect(s.users.records.get("amy")?.name).toBe("Amy Kay");
    expect(s.store.doc("users/amy")).toMatchObject({ displayName: "Amy Kay" });
    expect(s.store.doc("profiles/amy")).toMatchObject({ name: "Amy Kay", private: true, bio: "hidden" });
    expect(s.store.doc("profiles/amy")?.keywords).toEqual(expect.arrayContaining(["amy", "kay", "amyk"]));
  });

  it("sets the photo and header from the caller's own avatar uploads", async () => {
    avatar("p1");
    avatar("h1");
    const res = await s.call("PUT", "/v1/me/identity", { photoUploadId: "p1", headerUploadId: "h1" });
    expect(res.statusCode).toBe(200);
    const photo = `https://dl.test/v0/b/bucket/o/${encodeURIComponent("users/amy/profile/p1.jpg")}?alt=media&token=t`;
    expect(s.users.records.get("amy")?.photoUrl).toBe(photo);
    expect(s.store.doc("profiles/amy")).toMatchObject({ photoUrl: photo, headerUrl: expect.stringContaining("h1.jpg") });
  });

  it("deletes the old picture when it's replaced or removed", async () => {
    avatar("p1");
    s.media.files.set("users/amy/profile/p1.jpg", { data: Buffer.from("x") });
    await s.call("PUT", "/v1/me/identity", { photoUploadId: "p1" });
    await s.call("PUT", "/v1/me/identity", { photoUploadId: null });
    expect(s.media.files.has("users/amy/profile/p1.jpg")).toBe(false);
    expect(s.users.records.get("amy")?.photoUrl).toBeUndefined();
    expect(s.store.doc("profiles/amy")?.photoUrl).toBeNull();
  });

  it("refuses someone else's upload, other purposes, unfinished ones and visitors", async () => {
    avatar("b1", "ben");
    s.store.put("uploads/x1", { uid: "amy", purpose: "post", status: "ready", path: "users/amy/posts/a/x1.jpg", contentType: "image/jpeg" });
    avatar("w1", "amy", { status: "pending" });
    expect((await s.call("PUT", "/v1/me/identity", { photoUploadId: "b1" })).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/me/identity", { headerUploadId: "x1" })).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/me/identity", { photoUploadId: "w1" })).statusCode).toBe(412);
    expect((await s.call("PUT", "/v1/me/identity", {})).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/me/identity", { name: "" })).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/me/identity", { name: "Mallory" }, null)).statusCode).toBe(401);
    avatar("same");
    expect((await s.call("PUT", "/v1/me/identity", { photoUploadId: "same", headerUploadId: "same" })).statusCode).toBe(400);
  });

  it("never deletes files outside the caller's own profile folder", async () => {
    s.users.records.set("amy", { name: "Amy", photoUrl: `https://x/o/${encodeURIComponent("users/ben/profile/b.jpg")}?alt=media` });
    s.media.files.set("users/ben/profile/b.jpg", { data: Buffer.from("x") });
    await s.call("PUT", "/v1/me/identity", { photoUploadId: null });
    expect(s.media.files.has("users/ben/profile/b.jpg")).toBe(true);
  });
});

describe("read receipts", () => {
  it("turns them off and on for the caller", async () => {
    expect((await s.call("PUT", "/v1/me/read-receipts", { on: false })).statusCode).toBe(204);
    expect(s.store.doc("users/amy")?.readReceipts).toBe(false);
    expect((await s.call("PUT", "/v1/me/read-receipts", { on: "no" })).statusCode).toBe(400);
  });
});

describe("the Community Guidelines and Terms", () => {
  it("records agreeing to the current version, and says so", async () => {
    expect((await s.call("GET", "/v1/me/agreement")).json()).toEqual({ agreed: false, version: termsVersion });
    const res = await s.call("PUT", "/v1/me/agreement", { version: termsVersion });
    expect(res.statusCode).toBe(200);
    expect(res.headers["cache-control"]).toBe("private, no-store");
    expect(s.store.doc("users/amy")?.agreedTerms).toMatchObject({ version: termsVersion });
    expect((await s.call("GET", "/v1/me/agreement")).json()).toEqual({ agreed: true, version: termsVersion });
  });

  it("refuses an old version, a bad body and no sign-in", async () => {
    expect((await s.call("PUT", "/v1/me/agreement", { version: termsVersion + 1 })).statusCode).toBe(412);
    expect((await s.call("PUT", "/v1/me/agreement", { version: "1" })).statusCode).toBe(400);
    expect((await s.call("GET", "/v1/me/agreement", undefined, null)).statusCode).toBe(401);
    expect(s.store.doc("users/amy")?.agreedTerms).toBeUndefined();
  });

  it("asks again when the version goes up", async () => {
    s.store.put("users/amy", { agreedTerms: { version: termsVersion - 1 } });
    expect((await s.call("GET", "/v1/me/agreement")).json().agreed).toBe(false);
  });
});

describe("notification settings", () => {
  const prefs = () => s.store.doc("users/amy/settings/notifications");

  it("sets kinds for every team and for one, and resets a team", async () => {
    expect((await s.call("PUT", "/v1/me/notification-settings/category", { category: "chat", on: false })).statusCode).toBe(204);
    await s.call("PUT", "/v1/me/notification-settings/category", { category: "social", on: false });
    await s.call("PUT", "/v1/me/notification-settings/category", { category: "chat", on: true, teamId: "t1" });
    await s.call("PUT", "/v1/me/notification-settings/category", { category: "posts", on: false, teamId: "t1" });
    expect(prefs()).toMatchObject({ categories: { chat: false, social: false }, teams: { t1: { chat: true, posts: false } } });
    await s.call("DELETE", "/v1/me/notification-settings/teams/t1");
    expect(prefs()?.teams).toEqual({});
  });

  it("caps per-team settings at 200 teams, as the rules do", async () => {
    const teams = Object.fromEntries(Array.from({ length: 200 }, (_, i) => [`t${i}`, { chat: true }]));
    s.store.put("users/amy/settings/notifications", { teams });
    expect((await s.call("PUT", "/v1/me/notification-settings/category", { category: "chat", on: false, teamId: "new" })).statusCode).toBe(412);
    expect((await s.call("PUT", "/v1/me/notification-settings/category", { category: "chat", on: false, teamId: "t5" })).statusCode).toBe(204);
  });

  it("only sets per-team kinds per team, and only known kinds", async () => {
    expect((await s.call("PUT", "/v1/me/notification-settings/category", { category: "social", on: false, teamId: "t1" })).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/me/notification-settings/category", { category: "spam", on: true })).statusCode).toBe(400);
  });

  it("mutes and unmutes rooms and conversations", async () => {
    await s.call("PUT", "/v1/me/notification-settings/mute", { teamId: "t1", roomId: "general", muted: true });
    await s.call("PUT", "/v1/me/notification-settings/mute", { conversationId: "amy_ben", muted: true });
    await s.call("PUT", "/v1/me/notification-settings/mute", { conversationId: "amy_ben", muted: true });
    expect(prefs()?.mutedRooms).toEqual(["t1/general", "dm/amy_ben"]);
    await s.call("PUT", "/v1/me/notification-settings/mute", { teamId: "t1", roomId: "general", muted: false });
    expect(prefs()?.mutedRooms).toEqual(["dm/amy_ben"]);
    expect((await s.call("PUT", "/v1/me/notification-settings/mute", { teamId: "t1", muted: true })).statusCode).toBe(400);
  });
});
