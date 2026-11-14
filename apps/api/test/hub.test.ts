// The team hub's writes (team posts, events and responses, chat) against
// FakeStore, following the teams/{id}/posts, events and chats rules.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const media = new FakeMediaStorage();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media, now: () => now });
  const call = (method: "POST" | "PATCH" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "coach") =>
    app.inject({
      method,
      url,
      ...(body && { payload: body }),
      headers: uid ? { authorization: `Bearer token:${uid}` } : {},
    });
  return { store, users, media, call };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.users.records.set("coach", { name: "Casey Coach", email: "casey@x.test" });
  s.users.records.set("player", { name: "Pat Player", email: "pat@x.test" });
  s.store.put("teams/t1", {
    name: "Haze",
    kind: "team",
    memberIds: ["coach", "player", "helper"],
    members: { coach: "coach", player: "player", helper: "player" },
    memberPerms: { helper: ["manageEvents"] },
  });
});

function upload(id: string, data: Record<string, unknown>) {
  s.store.put(`uploads/${id}`, { status: "ready", contentType: "image/jpeg", actualSize: 10, ...data });
}

describe("team posts", () => {
  it("lets admins post, as themselves, never with their email as the name", async () => {
    s.users.records.set("coach", { email: "casey@x.test" });
    const res = await s.call("POST", "/v1/teams/t1/posts", { title: "Tryouts", body: " Sunday ", public: true });
    expect(res.statusCode).toBe(201);
    const post = s.store.doc(`teams/t1/posts/${res.json().id}`);
    expect(post).toMatchObject({ title: "Tryouts", body: "Sunday", public: true, authorId: "coach", images: [], links: [] });
    expect(post?.authorName).not.toContain("@x.test");
  });

  it("refuses players, outsiders and visitors", async () => {
    expect((await s.call("POST", "/v1/teams/t1/posts", { body: "hi" }, "player")).statusCode).toBe(403);
    expect((await s.call("POST", "/v1/teams/t1/posts", { body: "hi" }, "stranger")).statusCode).toBe(403);
    expect((await s.call("POST", "/v1/teams/t1/posts", { body: "hi" }, null)).statusCode).toBe(401);
    expect((await s.call("POST", "/v1/teams/nope/posts", { body: "hi" })).statusCode).toBe(404);
  });

  it("needs words or a photo, and only takes the caller's uploads for this post", async () => {
    expect((await s.call("POST", "/v1/teams/t1/posts", { body: "  " })).statusCode).toBe(400);
    upload("u1", { uid: "coach", purpose: "teamImage", targetId: "t1", itemId: "p1", path: "teams/t1/posts/p1/u1/u1.jpg" });
    upload("u2", { uid: "coach", purpose: "teamImage", targetId: "t2", itemId: "p1", path: "teams/t2/posts/p1/u2/u2.jpg" });
    upload("u3", { uid: "player", purpose: "teamImage", targetId: "t1", itemId: "p1", path: "teams/t1/posts/p1/u3/u3.jpg" });
    expect((await s.call("POST", "/v1/teams/t1/posts", { id: "p1", uploadIds: ["u2"] })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/teams/t1/posts", { id: "p1", uploadIds: ["u3"] })).statusCode).toBe(400);
    const ok = await s.call("POST", "/v1/teams/t1/posts", { id: "p1", uploadIds: ["u1"] });
    expect(ok.statusCode).toBe(201);
    expect(s.store.doc("teams/t1/posts/p1")?.images).toEqual([
      { path: "teams/t1/posts/p1/u1/u1.jpg", name: "u1.jpg", contentType: "image/jpeg", size: 10 },
    ]);
  });

  it("refuses bad links and fields the rule doesn't allow", async () => {
    expect((await s.call("POST", "/v1/teams/t1/posts", { body: "x", links: ["javascript:alert(1)"] })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/teams/t1/posts", { body: "x", authorId: "player" })).statusCode).toBe(400);
  });

  it("edits and deletes for admins only, removing dropped photos", async () => {
    s.store.put("teams/t1/posts/p1", {
      body: "old",
      images: [{ path: "teams/t1/posts/p1/u1/u1.jpg", name: "u1.jpg", contentType: "image/jpeg", size: 1 }],
      authorId: "coach",
    });
    s.media.files.set("teams/t1/posts/p1/u1/u1.jpg", { data: Buffer.from("x") });
    expect((await s.call("PATCH", "/v1/teams/t1/posts/p1", { body: "new" }, "player")).statusCode).toBe(403);
    expect((await s.call("PATCH", "/v1/teams/t1/posts/p1", { body: "new", keepImages: [] })).statusCode).toBe(200);
    expect(s.store.doc("teams/t1/posts/p1")).toMatchObject({ body: "new", images: [] });
    expect(s.media.files.has("teams/t1/posts/p1/u1/u1.jpg")).toBe(false);
    expect((await s.call("DELETE", "/v1/teams/t1/posts/p1", undefined, "player")).statusCode).toBe(403);
    expect((await s.call("DELETE", "/v1/teams/t1/posts/p1")).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/posts/p1")).toBeUndefined();
  });
});

const event = { title: "Practice", type: "practice", startsAt: "2026-11-20T18:00:00Z", location: "Field 3" };

describe("team events", () => {
  it("lets event managers create one, with a public copy when public", async () => {
    const res = await s.call("POST", "/v1/teams/t1/events", { ...event, public: true }, "helper");
    expect(res.statusCode).toBe(201);
    const id = res.json().id;
    expect(s.store.doc(`teams/t1/events/${id}`)).toMatchObject({
      title: "Practice",
      rsvps: {},
      reactions: {},
      votes: {},
      createdBy: "helper",
      public: true,
    });
    expect(s.store.doc(`teams/t1/events/${id}`)?.startsAt).toBeInstanceOf(Date);
    expect(Object.keys(s.store.doc(`teams/t1/publicEvents/${id}`) ?? {}).sort()).toEqual(
      ["endsAt", "location", "notes", "startsAt", "title", "type", "updatedAt"],
    );
  });

  it("refuses players and checks the details", async () => {
    expect((await s.call("POST", "/v1/teams/t1/events", event, "player")).statusCode).toBe(403);
    expect((await s.call("POST", "/v1/teams/t1/events", { ...event, title: "" })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/teams/t1/events", { ...event, endsAt: "2026-11-19T00:00:00Z" })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/teams/t1/events", { ...event, type: "party" })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/teams/t1/events", { ...event, rsvps: { player: "going" } })).statusCode).toBe(400);
  });

  it("resets votes when the poll changes, and drops the public copy when made private", async () => {
    const poll = { question: "Jerseys?", options: [{ id: "a", text: "Dark" }, { id: "b", text: "Light" }] };
    const id = (await s.call("POST", "/v1/teams/t1/events", { ...event, poll, public: true })).json().id;
    s.store.put(`teams/t1/events/${id}`, { ...s.store.doc(`teams/t1/events/${id}`), votes: { player: ["a"] } });
    await s.call("PATCH", `/v1/teams/t1/events/${id}`, { ...event, poll, public: true, notes: "Bring water" });
    expect(s.store.doc(`teams/t1/events/${id}`)?.votes).toEqual({ player: ["a"] });
    await s.call("PATCH", `/v1/teams/t1/events/${id}`, { ...event, poll: { ...poll, multiple: true } });
    expect(s.store.doc(`teams/t1/events/${id}`)?.votes).toEqual({});
    expect(s.store.doc(`teams/t1/publicEvents/${id}`)).toBeUndefined();
    expect((await s.call("DELETE", `/v1/teams/t1/events/${id}`, undefined, "player")).statusCode).toBe(403);
    expect((await s.call("DELETE", `/v1/teams/t1/events/${id}`)).statusCode).toBe(204);
  });

  describe("responses", () => {
    beforeEach(() => {
      s.store.put("teams/t1/events/e1", {
        ...event,
        poll: { question: "Q", options: [{ id: "a", text: "A" }, { id: "b", text: "B" }], multiple: false },
        rsvps: { coach: "going" },
        reactions: { coach: ["fire"] },
        votes: { coach: ["a"] },
      });
    });

    it("changes only the caller's own entries", async () => {
      expect((await s.call("PUT", "/v1/teams/t1/events/e1/rsvp", { status: "going" }, "player")).statusCode).toBe(204);
      expect((await s.call("PUT", "/v1/teams/t1/events/e1/reaction", { reaction: "clap", on: true }, "player")).statusCode).toBe(204);
      expect((await s.call("PUT", "/v1/teams/t1/events/e1/votes", { optionIds: ["b"] }, "player")).statusCode).toBe(204);
      expect(s.store.doc("teams/t1/events/e1")).toMatchObject({
        rsvps: { coach: "going", player: "going" },
        reactions: { coach: ["fire"], player: ["clap"] },
        votes: { coach: ["a"], player: ["b"] },
      });
      // Not going any more: their reactions and vote go with it.
      await s.call("PUT", "/v1/teams/t1/events/e1/rsvp", { status: "notGoing" }, "player");
      expect(s.store.doc("teams/t1/events/e1")).toMatchObject({
        rsvps: { coach: "going", player: "notGoing" },
        reactions: { coach: ["fire"] },
        votes: { coach: ["a"] },
      });
    });

    it("refuses outsiders, reactions and votes before going, and bad votes", async () => {
      expect((await s.call("PUT", "/v1/teams/t1/events/e1/rsvp", { status: "going" }, "stranger")).statusCode).toBe(404);
      expect((await s.call("PUT", "/v1/teams/t1/events/e1/rsvp", { status: "yes" }, "player")).statusCode).toBe(400);
      expect((await s.call("PUT", "/v1/teams/t1/events/e1/reaction", { reaction: "fire", on: true }, "player")).statusCode).toBe(412);
      await s.call("PUT", "/v1/teams/t1/events/e1/rsvp", { status: "going" }, "player");
      expect((await s.call("PUT", "/v1/teams/t1/events/e1/votes", { optionIds: ["a", "b"] }, "player")).statusCode).toBe(400);
      expect((await s.call("PUT", "/v1/teams/t1/events/e1/votes", { optionIds: ["zzz"] }, "player")).statusCode).toBe(400);
      expect((await s.call("PUT", "/v1/teams/t1/events/e1/reaction", { reaction: "poop", on: true }, "player")).statusCode).toBe(400);
    });

    it("keeps a community's events to their audience", async () => {
      s.store.put("teams/org", {
        kind: "organization",
        memberIds: ["coach", "player"],
        members: { coach: "owner", player: "player" },
        memberRoles: { player: ["juniors"] },
      });
      s.store.put("teams/org/events/staff", { ...event, audience: ["staff"], rsvps: {}, reactions: {}, votes: {} });
      s.store.put("teams/org/events/jr", { ...event, audience: ["juniors"], rsvps: {}, reactions: {}, votes: {} });
      expect((await s.call("PUT", "/v1/teams/org/events/staff/rsvp", { status: "going" }, "player")).statusCode).toBe(404);
      expect((await s.call("PUT", "/v1/teams/org/events/jr/rsvp", { status: "going" }, "player")).statusCode).toBe(204);
      // New community events get an audience.
      const id = (await s.call("POST", "/v1/teams/org/events", event)).json().id;
      expect(s.store.doc(`teams/org/events/${id}`)?.audience).toEqual(["everyone"]);
    });
  });
});

describe("team chat", () => {
  beforeEach(() => {
    s.store.put("teams/t1/chats/general", { name: "General", readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [], writeUsers: [] });
    s.store.put("teams/t1/chats/coaches", { name: "Coaches", readRoles: ["coach"], writeRoles: ["coach"], readUsers: [], writeUsers: [] });
    s.store.put("teams/t1/chats/news", { name: "News", readRoles: ["everyone"], writeRoles: ["coach"], readUsers: [], writeUsers: [] });
  });

  it("sends as the caller, quoting the message it answers from the room", async () => {
    s.store.put("teams/t1/chats/general/messages/m0", { authorId: "coach", authorName: "Casey", text: "Who's in?" });
    const res = await s.call("POST", "/v1/teams/t1/chats/general/messages", { text: " me ", replyTo: "m0" }, "player");
    expect(res.statusCode).toBe(201);
    expect(s.store.doc(`teams/t1/chats/general/messages/${res.json().id}`)).toMatchObject({
      authorId: "player",
      authorName: "Pat Player",
      text: "me",
      attachments: [],
      replyTo: { id: "m0", authorId: "coach", authorName: "Casey", text: "Who's in?" },
    });
  });

  it("refuses rooms the caller can't read or write, outsiders and muted members", async () => {
    expect((await s.call("POST", "/v1/teams/t1/chats/coaches/messages", { text: "hi" }, "player")).statusCode).toBe(404);
    expect((await s.call("POST", "/v1/teams/t1/chats/news/messages", { text: "hi" }, "player")).statusCode).toBe(403);
    expect((await s.call("POST", "/v1/teams/t1/chats/general/messages", { text: "hi" }, "stranger")).statusCode).toBe(404);
    expect((await s.call("POST", "/v1/teams/t1/chats/general/messages", { text: "" }, "player")).statusCode).toBe(400);
    s.store.put("limits/player", { mutedUntil: new Date(now + 60_000) });
    expect((await s.call("POST", "/v1/teams/t1/chats/general/messages", { text: "hi" }, "player")).statusCode).toBe(429);
  });

  it("only takes attachments uploaded for this room and message", async () => {
    upload("a1", { uid: "player", purpose: "chat", targetId: "teams/t1/chats/coaches", itemId: "m1", path: "x/a1.jpg" });
    expect((await s.call("POST", "/v1/teams/t1/chats/general/messages", { id: "m1", uploadIds: ["a1"] }, "player")).statusCode).toBe(400);
    upload("a2", { uid: "player", purpose: "chat", targetId: "teams/t1/chats/general", itemId: "m1", path: "teams/t1/chats/general/player/m1/a2.jpg" });
    expect((await s.call("POST", "/v1/teams/t1/chats/general/messages", { id: "m1", uploadIds: ["a2"] }, "player")).statusCode).toBe(201);
  });

  it("reacts as the caller only, from the offered emoji", async () => {
    s.store.put("teams/t1/chats/general/messages/m1", { authorId: "coach", text: "x", reactions: { coach: "🔥" } });
    expect((await s.call("PUT", "/v1/teams/t1/chats/general/messages/m1/reaction", { emoji: "👍" }, "player")).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/chats/general/messages/m1")?.reactions).toEqual({ coach: "🔥", player: "👍" });
    expect((await s.call("PUT", "/v1/teams/t1/chats/general/messages/m1/reaction", { emoji: "hello" }, "player")).statusCode).toBe(400);
    expect((await s.call("PUT", "/v1/teams/t1/chats/general/messages/m1/reaction", { emoji: null }, "player")).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/chats/general/messages/m1")?.reactions).toEqual({ coach: "🔥" });
    s.store.put("teams/t1/chats/coaches/messages/m2", { authorId: "coach", text: "secret" });
    expect((await s.call("PUT", "/v1/teams/t1/chats/coaches/messages/m2/reaction", { emoji: "👍" }, "player")).statusCode).toBe(404);
  });

  it("lets authors, the owner and moderators delete", async () => {
    s.store.put("teams/t1/chats/general/messages/m1", { authorId: "coach", text: "x" });
    s.store.put("teams/t1/chats/general/messages/m2", { authorId: "player", text: "y" });
    expect((await s.call("DELETE", "/v1/teams/t1/chats/general/messages/m1", undefined, "player")).statusCode).toBe(403);
    expect((await s.call("DELETE", "/v1/teams/t1/chats/general/messages/m2", undefined, "player")).statusCode).toBe(204);
    // A coach is an editor, so can moderate.
    s.store.put("teams/t1/chats/general/messages/m3", { authorId: "player", text: "z" });
    expect((await s.call("DELETE", "/v1/teams/t1/chats/general/messages/m3")).statusCode).toBe(204);
  });

  it("limits how fast one member sends", async () => {
    let last = 0;
    for (let i = 0; i < 61; i++) last = (await s.call("POST", "/v1/teams/t1/chats/general/messages", { text: `m${i}` }, "player")).statusCode;
    expect(last).toBe(429);
  });
});
