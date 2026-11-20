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

describe("polls", () => {
  const msg = (id: string) => s.store.doc(`teams/t1/chats/general/messages/${id}`);
  const vote = (id: string, options: number[], uid = "player") => s.call("PUT", `${room()}/messages/${id}/vote`, { options }, uid);
  const close = (id: string, uid: string) => s.call("POST", `${room()}/messages/${id}/close-poll`, undefined, uid);
  const create = (body: object, uid: string | null = "player") => s.call("POST", `${room()}/polls`, body, uid);

  it("lets anyone who can post ask, with an empty tally", async () => {
    const res = await create({ id: "q1", question: " Which day? ", options: ["Sat", "Sun"] });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toEqual({ id: "q1" });
    expect(msg("q1")).toMatchObject({
      authorId: "player",
      authorName: "Pat Player",
      text: "",
      attachments: [],
      poll: { question: "Which day?", options: ["Sat", "Sun"], multiple: false, closesAt: null, votes: {}, voterIds: [] },
      createdAt: new Date(now),
    });
    expect(s.store.doc("teams/t1/chats/general")?.lastAt).toEqual(new Date(now));
    expect((await create({ id: "q1", question: "Again?", options: ["a", "b"] })).statusCode).toBe(409);
  });

  it("checks the question, options and closing time", async () => {
    expect((await create({ question: "", options: ["a", "b"] })).statusCode).toBe(400);
    expect((await create({ question: "Q", options: ["a"] })).statusCode).toBe(400);
    expect((await create({ question: "Q", options: ["a", "b", "c", "d", "e", "f", "g"] })).statusCode).toBe(400);
    expect((await create({ question: "Q", options: ["Yes", "yes"] })).statusCode).toBe(400);
    expect((await create({ question: "Q", options: ["a", "b"], closesAt: new Date(now - hour).toISOString() })).statusCode).toBe(400);
    expect((await create({ question: "Q", options: ["a", "b"], votes: { x: [0] } })).statusCode).toBe(400);
    const ok = await create({ id: "q2", question: "Q", options: ["a", "b"], multiple: true, closesAt: new Date(now + hour).toISOString() });
    expect(ok.statusCode).toBe(201);
    expect(msg("q2")?.poll).toMatchObject({ multiple: true, closesAt: new Date(now + hour) });
  });

  it("refuses people who can't post in the room", async () => {
    s.store.put("teams/t1/chats/news", { name: "News", readRoles: ["everyone"], writeRoles: ["coach"], readUsers: [], writeUsers: [] });
    expect((await s.call("POST", `${room("news")}/polls`, { question: "Q", options: ["a", "b"] }, "player")).statusCode).toBe(403);
    expect((await s.call("POST", `${room("coaches")}/polls`, { question: "Q", options: ["a", "b"] }, "player")).statusCode).toBe(404);
    expect((await create({ question: "Q", options: ["a", "b"] }, "stranger")).statusCode).toBe(404);
    expect((await create({ question: "Q", options: ["a", "b"] }, null)).statusCode).toBe(401);
  });

  it("keeps one choice on a single-choice poll; [] takes it back", async () => {
    await create({ id: "q1", question: "Which day?", options: ["Sat", "Sun"] }, "coach");
    expect((await vote("q1", [0])).statusCode).toBe(204);
    expect((await vote("q1", [1], "chats")).statusCode).toBe(204);
    expect(msg("q1")?.poll).toMatchObject({ votes: { player: [0], chats: [1] }, voterIds: ["player", "chats"] });
    expect((await vote("q1", [1])).statusCode).toBe(204);
    expect((msg("q1")?.poll as { votes: object }).votes).toEqual({ player: [1], chats: [1] });
    expect((await vote("q1", [0, 1])).statusCode).toBe(400);
    expect((await vote("q1", [2])).statusCode).toBe(400);
    expect((await vote("q1", [])).statusCode).toBe(204);
    expect(msg("q1")?.poll).toMatchObject({ votes: { chats: [1] }, voterIds: ["chats"] });
    // Everything else on the poll stays.
    expect(msg("q1")?.poll).toMatchObject({ question: "Which day?", options: ["Sat", "Sun"], multiple: false });
  });

  it("takes several choices on a multiple-choice poll", async () => {
    await create({ id: "q1", question: "Which?", options: ["a", "b", "c"], multiple: true });
    expect((await vote("q1", [2, 0, 2])).statusCode).toBe(204);
    expect((msg("q1")?.poll as { votes: object }).votes).toEqual({ player: [0, 2] });
  });

  it("lets readers vote, not outsiders; not on plain messages or deleted polls", async () => {
    s.store.put("teams/t1/chats/news", { name: "News", readRoles: ["everyone"], writeRoles: ["coach"], readUsers: [], writeUsers: [] });
    s.store.put("teams/t1/chats/news/messages/n1", { authorId: "coach", text: "", attachments: [], poll: { question: "Q", options: ["a", "b"], multiple: false, votes: {}, voterIds: [] } });
    expect((await s.call("PUT", `${room("news")}/messages/n1/vote`, { options: [0] }, "player")).statusCode).toBe(204);
    s.store.put("teams/t1/chats/coaches/messages/c1", { authorId: "coach", text: "", attachments: [], poll: { question: "Q", options: ["a", "b"], multiple: false } });
    expect((await s.call("PUT", `${room("coaches")}/messages/c1/vote`, { options: [0] }, "player")).statusCode).toBe(404);
    expect((await vote("m1", [0], "stranger")).statusCode).toBe(404);
    expect((await vote("m1", [0])).statusCode).toBe(404);
    expect((await vote("gone", [0])).statusCode).toBe(404);
  });

  it("closes early for its author or chat managers, and then takes no votes", async () => {
    await create({ id: "q1", question: "Which day?", options: ["Sat", "Sun"] });
    expect((await close("q1", "coach")).statusCode).toBe(204); // the owner manages chats
    await create({ id: "q2", question: "Which day?", options: ["Sat", "Sun"] });
    expect((await close("q2", "planner")).statusCode).toBe(403);
    expect((await close("q2", "player")).statusCode).toBe(204);
    expect(msg("q2")?.poll).toMatchObject({ closedAt: new Date(now), closedBy: "player" });
    expect((await vote("q2", [0], "chats")).statusCode).toBe(412);
    // Closing again keeps who closed it.
    expect((await close("q2", "chats")).statusCode).toBe(204);
    expect(msg("q2")?.poll).toMatchObject({ closedBy: "player" });
  });

  it("stops taking votes at its closing time", async () => {
    s.store.put("teams/t1/chats/general/messages/old", {
      authorId: "coach",
      text: "",
      attachments: [],
      poll: { question: "Q", options: ["a", "b"], multiple: false, closesAt: new Date(now - 1), votes: {}, voterIds: [] },
    });
    expect((await vote("old", [0])).statusCode).toBe(412);
  });

  it("quotes the question in replies, and keeps polls out of ordinary messages", async () => {
    await create({ id: "q1", question: "Which day?", options: ["Sat", "Sun"] });
    const res = await s.call("POST", `${room()}/messages`, { text: "Sat", replyTo: "q1" }, "chats");
    expect(s.store.doc(`teams/t1/chats/general/messages/${res.json().id}`)?.replyTo).toMatchObject({ text: "📊 Which day?" });
    expect((await s.call("POST", `${room()}/messages`, { text: "x", poll: { question: "Q" } }, "player")).statusCode).toBe(400);
  });

  it("goes when its message is deleted", async () => {
    await create({ id: "q1", question: "Which day?", options: ["Sat", "Sun"] });
    expect((await s.call("DELETE", `${room()}/messages/q1`, undefined, "player")).statusCode).toBe(204);
    expect(msg("q1")).toBeUndefined();
    expect((await vote("q1", [0], "chats")).statusCode).toBe(404);
  });
});
