// Direct and group conversations against FakeStore, following the
// conversations rules in firestore.rules.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
  const call = (method: "POST" | "PATCH" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "amy") =>
    app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
  return { store, users, call };
}

let s: ReturnType<typeof setup>;
const follow = (follower: string, followed: string) => s.store.put(`users/${follower}/follows/user_${followed}`, { at: new Date(now) });

beforeEach(() => {
  s = setup();
  for (const [uid, name] of [["amy", "Amy"], ["ben", "Ben"], ["cal", "Cal"], ["dee", "Dee"]]) {
    s.store.put(`profiles/${uid}`, { name });
    s.users.records.set(uid!, { name, email: `${uid}@x.test` });
  }
});

describe("starting a conversation", () => {
  it("goes straight to their inbox when they follow you", async () => {
    follow("ben", "amy");
    const res = await s.call("POST", "/v1/conversations", { with: "ben" });
    expect(res.json()).toEqual({ id: "amy_ben", status: "accepted" });
    expect(s.store.doc("conversations/amy_ben")).toMatchObject({
      participants: ["amy", "ben"],
      names: { amy: "Amy", ben: "Ben" },
      lastMessage: "",
      readAt: {},
      status: "accepted",
    });
  });

  it("is a request when they don't follow you, and follows their policy", async () => {
    expect((await s.call("POST", "/v1/conversations", { with: "ben" })).json()).toEqual({ id: "amy_ben", status: "request" });
    expect(s.store.doc("conversations/amy_ben")?.requestedOf).toBe("ben");
    s.store.put("users/cal", { messagePolicy: "following" });
    expect((await s.call("POST", "/v1/conversations", { with: "cal" })).statusCode).toBe(403);
    s.store.put("users/dee", { messagePolicy: "followers" });
    expect((await s.call("POST", "/v1/conversations", { with: "dee" })).statusCode).toBe(403);
    follow("amy", "dee");
    expect((await s.call("POST", "/v1/conversations", { with: "dee" })).json().status).toBe("request");
    s.store.put("users/cal", { messagePolicy: "nobody" });
    follow("cal", "amy");
    expect((await s.call("POST", "/v1/conversations", { with: "cal" })).statusCode).toBe(403);
  });

  it("refuses yourself, unknown players and visitors", async () => {
    expect((await s.call("POST", "/v1/conversations", { with: "amy" })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/conversations", { with: "ghost" })).statusCode).toBe(404);
    expect((await s.call("POST", "/v1/conversations", { with: "ben" }, null)).statusCode).toBe(401);
  });
});

describe("messages", () => {
  beforeEach(() => {
    s.store.put("conversations/amy_ben", {
      participants: ["amy", "ben"],
      names: { amy: "Amy", ben: "Ben" },
      readAt: { ben: new Date(now - 1000) },
      status: "accepted",
    });
  });

  it("sends with the inbox preview and the sender's read time", async () => {
    const res = await s.call("POST", "/v1/conversations/amy_ben/messages", { text: "  Pickup at 6?  " });
    expect(res.statusCode).toBe(201);
    expect(s.store.doc(`conversations/amy_ben/messages/${res.json().id}`)).toMatchObject({ authorId: "amy", authorName: "Amy", text: "Pickup at 6?" });
    expect(s.store.doc("conversations/amy_ben")).toMatchObject({
      lastMessage: "Pickup at 6?",
      lastSenderId: "amy",
      readAt: { ben: new Date(now - 1000), amy: new Date(now) },
    });
  });

  it("keeps outsiders out, even with a guessed id", async () => {
    expect((await s.call("POST", "/v1/conversations/amy_ben/messages", { text: "hi" }, "cal")).statusCode).toBe(404);
    expect((await s.call("POST", "/v1/conversations/ben_amy/messages", { text: "hi" })).statusCode).toBe(404);
    expect((await s.call("POST", "/v1/conversations/amy_ben%2Fx/messages", { text: "hi" })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/conversations/amy_ben/read", undefined, "cal")).statusCode).toBe(404);
  });

  it("holds whoever a request waits on until they accept", async () => {
    s.store.put("conversations/amy_ben", { participants: ["amy", "ben"], names: {}, readAt: {}, status: "request", requestedOf: "ben" });
    expect((await s.call("POST", "/v1/conversations/amy_ben/messages", { text: "hi" }, "ben")).statusCode).toBe(412);
    // No read receipt while it waits, but their own read time is kept.
    await s.call("POST", "/v1/conversations/amy_ben/read", undefined, "ben");
    expect(s.store.doc("conversations/amy_ben")?.readAt).toEqual({});
    expect(s.store.doc("users/ben/dmReads/amy_ben")?.readAt).toEqual(new Date(now));
    expect((await s.call("PUT", "/v1/conversations/amy_ben/request", { accept: true }, "amy")).statusCode).toBe(412);
    expect((await s.call("PUT", "/v1/conversations/amy_ben/request", { accept: true }, "ben")).statusCode).toBe(204);
    expect((await s.call("POST", "/v1/conversations/amy_ben/messages", { text: "hi" }, "ben")).statusCode).toBe(201);
  });

  it("declining clears it for them", async () => {
    s.store.put("conversations/amy_ben", { participants: ["amy", "ben"], names: {}, readAt: {}, status: "request", requestedOf: "ben" });
    await s.call("PUT", "/v1/conversations/amy_ben/request", { accept: false }, "ben");
    expect(s.store.doc("conversations/amy_ben")?.status).toBe("declined");
    expect(s.store.doc("users/ben/dmReads/amy_ben")?.clearedAt).toEqual(new Date(now));
  });

  it("only takes attachments uploaded for this conversation and message", async () => {
    s.store.put("uploads/u1", { uid: "amy", purpose: "chat", targetId: "conversations/amy_cal", itemId: "m1", status: "ready", path: "x.jpg", contentType: "image/jpeg" });
    expect((await s.call("POST", "/v1/conversations/amy_ben/messages", { id: "m1", uploadIds: ["u1"] })).statusCode).toBe(400);
    s.store.put("uploads/u2", {
      uid: "amy",
      purpose: "chat",
      targetId: "conversations/amy_ben",
      itemId: "m1",
      status: "ready",
      path: "conversations/amy_ben/amy/m1/u2.jpg",
      contentType: "image/jpeg",
    });
    expect((await s.call("POST", "/v1/conversations/amy_ben/messages", { id: "m1", uploadIds: ["u2"] })).statusCode).toBe(201);
    expect(s.store.doc("conversations/amy_ben")?.lastMessage).toBe("📷 Photo");
  });

  it("keeps a file's own name and size on the message", async () => {
    s.store.put("uploads/u3", {
      uid: "amy",
      purpose: "chat",
      targetId: "conversations/amy_ben",
      itemId: "m2",
      status: "ready",
      path: "conversations/amy_ben/amy/m2/u3-Line calls.pdf",
      name: "Line calls.pdf",
      contentType: "application/pdf",
      actualSize: 2048,
    });
    expect((await s.call("POST", "/v1/conversations/amy_ben/messages", { id: "m2", uploadIds: ["u3"] })).statusCode).toBe(201);
    expect(s.store.doc("conversations/amy_ben/messages/m2")?.attachments).toEqual([
      { path: "conversations/amy_ben/amy/m2/u3-Line calls.pdf", name: "Line calls.pdf", contentType: "application/pdf", size: 2048 },
    ]);
  });

  it("names a compressed photo as it's saved, not as it was sent", async () => {
    s.store.put("uploads/u4", {
      uid: "amy",
      purpose: "chat",
      targetId: "conversations/amy_ben",
      itemId: "m3",
      status: "ready",
      path: "conversations/amy_ben/amy/m3/u4.jpg",
      name: "IMG_1.HEIC",
      contentType: "image/jpeg",
      actualSize: 4096,
    });
    expect((await s.call("POST", "/v1/conversations/amy_ben/messages", { id: "m3", uploadIds: ["u4"] })).statusCode).toBe(201);
    expect(s.store.doc("conversations/amy_ben/messages/m3")?.attachments).toEqual([
      { path: "conversations/amy_ben/amy/m3/u4.jpg", name: "u4.jpg", contentType: "image/jpeg", size: 4096 },
    ]);
  });

  it("reacts as the caller and deletes only their own", async () => {
    s.store.put("conversations/amy_ben/messages/m1", { authorId: "ben", text: "yo" });
    expect((await s.call("PUT", "/v1/conversations/amy_ben/messages/m1/reaction", { emoji: "🔥" })).statusCode).toBe(204);
    expect(s.store.doc("conversations/amy_ben/messages/m1")?.reactions).toEqual({ amy: "🔥" });
    expect((await s.call("PUT", "/v1/conversations/amy_ben/messages/m1/reaction", { emoji: "‼️" })).statusCode).toBe(204);
    expect((await s.call("PUT", "/v1/conversations/amy_ben/messages/m1/reaction", { emoji: "yes" })).statusCode).toBe(400);
    expect((await s.call("DELETE", "/v1/conversations/amy_ben/messages/m1")).statusCode).toBe(403);
    expect((await s.call("DELETE", "/v1/conversations/amy_ben/messages/m1", undefined, "ben")).statusCode).toBe(204);
  });

  it("marks and clears typing for participants only", async () => {
    expect((await s.call("PUT", "/v1/conversations/amy_ben/typing", { typing: true })).statusCode).toBe(204);
    expect(s.store.doc("conversations/amy_ben/typing/amy")).toEqual({ at: new Date(now) });
    expect((await s.call("PUT", "/v1/conversations/amy_ben/typing", { typing: true }, "cal")).statusCode).toBe(404);
    await s.call("PUT", "/v1/conversations/amy_ben/typing", { typing: false });
    expect(s.store.doc("conversations/amy_ben/typing/amy")).toBeUndefined();
  });

  it("archives and clears for the caller only", async () => {
    await s.call("PUT", "/v1/conversations/amy_ben/archive", { archived: true });
    expect(s.store.doc("users/amy/dmReads/amy_ben")?.archivedAt).toEqual(new Date(now));
    await s.call("PUT", "/v1/conversations/amy_ben/archive", { archived: false });
    expect(s.store.doc("users/amy/dmReads/amy_ben")).not.toHaveProperty("archivedAt");
    await s.call("POST", "/v1/conversations/amy_ben/clear");
    expect(s.store.doc("users/amy/dmReads/amy_ben")?.clearedAt).toEqual(new Date(now));
    expect(s.store.doc("users/ben/dmReads/amy_ben")).toBeUndefined();
  });
});

describe("groups", () => {
  it("adds only people who follow the adder and take messages, up to ten", async () => {
    follow("ben", "amy");
    follow("cal", "amy");
    s.store.put("users/cal", { messagePolicy: "nobody" });
    const res = await s.call("POST", "/v1/conversations/groups", { name: "Carpool", members: ["ben", "cal", "dee"] });
    expect(res.statusCode).toBe(201);
    const { id, notAdded } = res.json();
    expect(id).toMatch(/^g-[A-Za-z0-9]+$/);
    expect(notAdded.sort()).toEqual(["Cal", "Dee"]);
    expect(s.store.doc(`conversations/${id}`)).toMatchObject({ kind: "group", createdBy: "amy", participants: ["amy", "ben"], name: "Carpool" });
  });

  it("lets members leave and rename; only the creator removes others; outsiders get nothing", async () => {
    s.store.put("conversations/g-abc", { kind: "group", createdBy: "amy", participants: ["amy", "ben", "cal"], names: {} });
    expect((await s.call("DELETE", "/v1/conversations/g-abc/members/cal", undefined, "ben")).statusCode).toBe(403);
    expect((await s.call("DELETE", "/v1/conversations/g-abc/members/ben", undefined, "ben")).statusCode).toBe(204);
    expect((await s.call("DELETE", "/v1/conversations/g-abc/members/cal")).statusCode).toBe(204);
    expect(s.store.doc("conversations/g-abc")?.participants).toEqual(["amy"]);
    expect((await s.call("PATCH", "/v1/conversations/g-abc", { name: "Lines" })).statusCode).toBe(204);
    expect((await s.call("PATCH", "/v1/conversations/g-abc", { name: "Mine" }, "dee")).statusCode).toBe(404);
    expect((await s.call("POST", "/v1/conversations/g-abc/messages", { text: "hi" }, "ben")).statusCode).toBe(404);
  });
});
