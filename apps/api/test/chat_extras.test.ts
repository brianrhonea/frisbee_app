// Pinned messages and event cards in team rooms (redesign F2, F3), against
// FakeStore. API-only: firestore.rules lets no client write these fields.
import { chatPinsMax } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
const hour = 3600_000;

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
  const call = (method: "POST" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "coach") =>
    app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
  return { store, users, call };
}

let s: ReturnType<typeof setup>;
const room = (r = "general") => `/v1/teams/t1/chats/${r}`;
const pin = (m: string, r = "general") => `${room(r)}/messages/${m}/pin`;

beforeEach(() => {
  s = setup();
  s.users.records.set("coach", { name: "Casey Coach" });
  s.users.records.set("player", { name: "Pat Player" });
  s.users.records.set("chats", { name: "Chat Manager" });
  s.store.put("teams/t1", {
    name: "Haze",
    kind: "team",
    memberIds: ["coach", "player", "chats", "planner"],
    members: { coach: "coach", player: "player", chats: "player", planner: "player" },
    memberPerms: { chats: ["manageChats"], planner: ["manageEvents"] },
  });
  s.store.put("teams/t1/chats/general", { name: "General", readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [], writeUsers: [] });
  s.store.put("teams/t1/chats/coaches", { name: "Coaches", readRoles: ["coach"], writeRoles: ["coach"], readUsers: [], writeUsers: [] });
  for (let i = 0; i < 12; i++) s.store.put(`teams/t1/chats/general/messages/m${i}`, { authorId: "player", authorName: "Pat", text: `hi ${i}` });
});

describe("pins", () => {
  it("lets chat managers pin and unpin, newest first", async () => {
    expect((await s.call("PUT", pin("m1"))).statusCode).toBe(204);
    expect((await s.call("PUT", pin("m2"), {}, "chats")).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/chats/general")?.pins).toEqual(["m2", "m1"]);
    expect(s.store.doc("teams/t1/chats/general/messages/m1")).toMatchObject({ pinnedAt: new Date(now), pinnedBy: "coach" });
    expect((await s.call("DELETE", pin("m1"), undefined, "chats")).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/chats/general")?.pins).toEqual(["m2"]);
    expect(s.store.doc("teams/t1/chats/general/messages/m1")).not.toHaveProperty("pinnedAt");
    expect(s.store.doc("teams/t1/chats/general/messages/m1")).not.toHaveProperty("pinnedBy");
  });

  it("refuses players, outsiders, visitors, and rooms the manager can't read", async () => {
    expect((await s.call("PUT", pin("m1"), {}, "player")).statusCode).toBe(403);
    expect((await s.call("DELETE", pin("m1"), undefined, "player")).statusCode).toBe(403);
    expect((await s.call("PUT", pin("m1"), {}, "stranger")).statusCode).toBe(404);
    expect((await s.call("PUT", pin("m1"), {}, null)).statusCode).toBe(401);
    s.store.put("teams/t1/chats/coaches/messages/c1", { authorId: "coach", text: "x" });
    expect((await s.call("PUT", pin("c1", "coaches"), {}, "chats")).statusCode).toBe(404);
    expect((await s.call("PUT", pin("gone"))).statusCode).toBe(404);
  });

  it(`holds ${chatPinsMax} a room, unless one is unpinned in the same write`, async () => {
    for (let i = 0; i < chatPinsMax; i++) expect((await s.call("PUT", pin(`m${i}`))).statusCode).toBe(204);
    const full = await s.call("PUT", pin("m10"));
    expect(full.statusCode).toBe(412);
    expect(full.json().error.message).toContain("Unpin one first");
    // Pinning one that's already pinned is fine.
    expect((await s.call("PUT", pin("m3"))).statusCode).toBe(204);
    expect((await s.call("PUT", pin("m10"), { unpin: "m0" })).statusCode).toBe(204);
    const pins = s.store.doc("teams/t1/chats/general")?.pins as string[];
    expect(pins).toHaveLength(chatPinsMax);
    expect(pins[0]).toBe("m10");
    expect(pins).not.toContain("m0");
    expect(s.store.doc("teams/t1/chats/general/messages/m0")).not.toHaveProperty("pinnedAt");
  });

  it("forgets pins whose message was deleted, there or through the API", async () => {
    for (let i = 0; i < chatPinsMax; i++) await s.call("PUT", pin(`m${i}`));
    // The app deletes straight from Firestore: the next pin drops the stale id.
    s.store.docs.delete("teams/t1/chats/general/messages/m4");
    expect((await s.call("PUT", pin("m10"))).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/chats/general")?.pins).not.toContain("m4");
    expect((await s.call("DELETE", `${room()}/messages/m10`)).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/chats/general")?.pins).not.toContain("m10");
  });
});

describe("event cards", () => {
  beforeEach(() => {
    s.store.put("teams/t1/events/e1", { title: "Practice: zone O", startsAt: new Date(now + 24 * hour), audience: [] });
    s.store.put("teams/t1/events/old", { title: "Last week", startsAt: new Date(now - 7 * 24 * hour) });
  });

  it("posts the event as a card, with its title for the push", async () => {
    const res = await s.call("POST", `${room()}/event-shares`, { eventId: "e1" }, "planner");
    expect(res.statusCode).toBe(201);
    expect(s.store.doc(`teams/t1/chats/general/messages/${res.json().id}`)).toMatchObject({
      authorId: "planner",
      text: "",
      attachments: [],
      event: { id: "e1", title: "Practice: zone O" },
      createdAt: new Date(now),
    });
    expect(s.store.doc("teams/t1/chats/general")?.lastAt).toEqual(new Date(now));
  });

  it("quotes a shared event's title in replies", async () => {
    await s.call("POST", `${room()}/event-shares`, { id: "share1", eventId: "e1" });
    const res = await s.call("POST", `${room()}/messages`, { text: "in", replyTo: "share1" }, "player");
    expect(s.store.doc(`teams/t1/chats/general/messages/${res.json().id}`)?.replyTo).toMatchObject({ text: "📅 Practice: zone O" });
  });

  it("needs someone who adds events and can post in the room", async () => {
    expect((await s.call("POST", `${room()}/event-shares`, { eventId: "e1" }, "player")).statusCode).toBe(403);
    expect((await s.call("POST", `${room()}/event-shares`, { eventId: "e1" }, "stranger")).statusCode).toBe(404);
    expect((await s.call("POST", `${room("coaches")}/event-shares`, { eventId: "e1" }, "planner")).statusCode).toBe(404);
    s.store.put("teams/t1/chats/news", { name: "News", readRoles: ["everyone"], writeRoles: ["coach"], readUsers: [], writeUsers: [] });
    expect((await s.call("POST", `${room("news")}/event-shares`, { eventId: "e1" }, "planner")).statusCode).toBe(403);
  });

  it("refuses deleted and finished events, and a community's events not for everyone", async () => {
    expect((await s.call("POST", `${room()}/event-shares`, { eventId: "nope" })).statusCode).toBe(404);
    expect((await s.call("POST", `${room()}/event-shares`, { eventId: "old" })).statusCode).toBe(412);
    s.store.put("teams/t1", { ...s.store.doc("teams/t1"), kind: "organization" });
    s.store.put("teams/t1/events/e2", { title: "Coaches only", startsAt: new Date(now + hour), audience: ["coach"] });
    expect((await s.call("POST", `${room()}/event-shares`, { eventId: "e2" })).statusCode).toBe(412);
    s.store.put("teams/t1/events/e3", { title: "All", startsAt: new Date(now + hour), audience: ["everyone"] });
    expect((await s.call("POST", `${room()}/event-shares`, { eventId: "e3" })).statusCode).toBe(201);
  });

  it("keeps clients from slipping an event into an ordinary message", async () => {
    expect((await s.call("POST", `${room()}/messages`, { text: "x", event: { id: "e1" } }, "player")).statusCode).toBe(400);
  });
});
