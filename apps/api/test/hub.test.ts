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

  describe("poll votes survive edits that don't change the poll", () => {
    const poll = { question: "Jerseys?", options: [{ id: "a", text: "Dark" }, { id: "b", text: "Light" }] };
    const make = async () => {
      const id = (await s.call("POST", "/v1/teams/t1/events", { ...event, poll })).json().id as string;
      // Stored with its keys in another order (Firestore's order isn't ours) and a null-ish `multiple`.
      s.store.put(`teams/t1/events/${id}`, {
        ...s.store.doc(`teams/t1/events/${id}`),
        poll: { options: [{ text: "Dark", id: "a" }, { text: "Light", id: "b" }], multiple: false, question: "Jerseys?" },
        votes: { player: ["a"] },
      });
      return id;
    };

    it("a stored poll with its keys in another order keeps its votes when only the notes change", async () => {
      const id = await make();
      await s.call("PATCH", `/v1/teams/t1/events/${id}`, { ...event, poll, notes: "Bring water" });
      expect(s.store.doc(`teams/t1/events/${id}`)?.votes).toEqual({ player: ["a"] });
    });

    it("a changed option text, a reordered option, or a new question resets them", async () => {
      for (const changed of [
        { ...poll, options: [{ id: "a", text: "Navy" }, { id: "b", text: "Light" }] },
        { ...poll, options: [{ id: "b", text: "Light" }, { id: "a", text: "Dark" }] },
        { ...poll, question: "Which jerseys?" },
      ]) {
        const id = await make();
        await s.call("PATCH", `/v1/teams/t1/events/${id}`, { ...event, poll: changed });
        expect(s.store.doc(`teams/t1/events/${id}`)?.votes, JSON.stringify(changed)).toEqual({});
      }
    });

    it("a missing poll and a null poll are the same: no votes wiped on an event without one", async () => {
      const id = (await s.call("POST", "/v1/teams/t1/events", event)).json().id as string;
      const stored = { ...s.store.doc(`teams/t1/events/${id}`) };
      delete stored.poll;
      s.store.put(`teams/t1/events/${id}`, { ...stored, votes: { player: ["x"] } });
      await s.call("PATCH", `/v1/teams/t1/events/${id}`, { ...event, notes: "n" });
      expect(s.store.doc(`teams/t1/events/${id}`)?.votes).toEqual({ player: ["x"] });
    });

    it("a series edit with scope=following and an unchanged poll keeps every later event's votes", async () => {
      const weekly = { ...event, poll, endsAt: "2026-11-20T20:00:00Z", repeat: { freq: "weekly", until: "2026-12-11" }, timeZone: "America/New_York" };
      const first = (await s.call("POST", "/v1/teams/t1/events", weekly)).json().id as string;
      const all = [0, 1, 2, 3].map((i) => first.replace(/_0$/, `_${i}`));
      for (const id of all) {
        s.store.put(`teams/t1/events/${id}`, {
          ...s.store.doc(`teams/t1/events/${id}`),
          poll: { options: [{ text: "Dark", id: "a" }, { text: "Light", id: "b" }], multiple: false, question: "Jerseys?" },
          votes: { player: ["b"] },
        });
      }
      const res = await s.call("PATCH", `/v1/teams/t1/events/${all[1]}?scope=following`, { ...weekly, notes: "Bring water", startsAt: "2026-11-27T18:00:00Z", endsAt: "2026-11-27T20:00:00Z" });
      expect(res.statusCode).toBe(200);
      for (const id of all.slice(1)) expect(s.store.doc(`teams/t1/events/${id}`)?.votes).toEqual({ player: ["b"] });
    });
  });

  describe("repeating", () => {
    const weekly = { ...event, endsAt: "2026-11-20T20:00:00Z", repeat: { freq: "weekly", until: "2026-12-11" }, timeZone: "America/New_York" };
    const ids = (first: string) => [0, 1, 2, 3].map((i) => first.replace(/_0$/, `_${i}`));

    it("writes one event per week, each with the series, at the same local time", async () => {
      const res = await s.call("POST", "/v1/teams/t1/events", { ...weekly, public: true });
      expect(res.statusCode).toBe(201);
      const first = res.json().id as string;
      expect(first).toMatch(/_0$/);
      const all = ids(first).map((id) => s.store.doc(`teams/t1/events/${id}`)!);
      expect(all.map((e) => (e.startsAt as Date).toISOString())).toEqual([
        "2026-11-20T18:00:00.000Z",
        "2026-11-27T18:00:00.000Z",
        "2026-12-04T18:00:00.000Z",
        "2026-12-11T18:00:00.000Z",
      ]);
      expect(all.map((e) => (e.endsAt as Date).toISOString())[3]).toBe("2026-12-11T20:00:00.000Z");
      expect(all[2]!.series).toEqual({ id: first.slice(0, -2), index: 2, count: 4, freq: "weekly", until: "2026-12-11" });
      // The public copy has the details only (the publicEvents rule).
      expect(s.store.doc(`teams/t1/publicEvents/${ids(first)[3]}`)?.title).toBe("Practice");
      expect(s.store.doc(`teams/t1/publicEvents/${ids(first)[3]}`)?.series).toBeUndefined();
      expect(s.store.doc(`teams/t1/events/${first.replace(/_0$/, "_4")}`)).toBeUndefined();
    });

    it("keeps the wall-clock time across a clock change", async () => {
      // 6 pm in New York on Oct 30 (EDT) and Nov 6 (EST).
      const res = await s.call("POST", "/v1/teams/t1/events", {
        ...event,
        startsAt: "2026-10-30T22:00:00Z",
        repeat: { freq: "weekly", until: "2026-11-06" },
        timeZone: "America/New_York",
      });
      const second = s.store.doc(`teams/t1/events/${(res.json().id as string).replace(/_0$/, "_1")}`)!;
      expect((second.startsAt as Date).toISOString()).toBe("2026-11-06T23:00:00.000Z");
    });

    it("refuses repeats that are too long, end too soon, or have no time zone", async () => {
      const post = (repeat: object, timeZone: string | undefined = "UTC") =>
        s.call("POST", "/v1/teams/t1/events", { ...event, repeat, ...(timeZone && { timeZone }) });
      expect((await post({ freq: "daily", until: "2027-11-30" })).statusCode).toBe(400);
      expect((await post({ freq: "daily", until: "2027-03-30" })).statusCode).toBe(400); // over 100
      expect((await post({ freq: "weekly", until: "2026-11-19" })).statusCode).toBe(400);
      expect((await post({ freq: "weekly", until: "2026-12-11" }, "")).statusCode).toBe(400);
      expect((await post({ freq: "weekly", until: "2026-12-11" }, "Mars/Olympus")).statusCode).toBe(400);
      expect((await post({ freq: "hourly", until: "2026-12-11" })).statusCode).toBe(400);
    });

    it("edits this and following: same change of time, RSVPs kept, earlier ones untouched", async () => {
      const first = (await s.call("POST", "/v1/teams/t1/events", weekly)).json().id as string;
      const [e0, e1, e2, e3] = ids(first);
      s.store.put(`teams/t1/events/${e2}`, { ...s.store.doc(`teams/t1/events/${e2}`), rsvps: { player: "going" } });
      // Move the second one from 1 pm to 2 pm local and rename it.
      const res = await s.call(
        "PATCH",
        `/v1/teams/t1/events/${e1}?scope=following`,
        { ...event, title: "Late practice", startsAt: "2026-11-27T19:00:00Z", endsAt: "2026-11-27T20:30:00Z", timeZone: "America/New_York" },
      );
      expect(res.statusCode).toBe(200);
      expect(s.store.doc(`teams/t1/events/${e0}`)?.title).toBe("Practice");
      const later = [e1, e2, e3].map((id) => s.store.doc(`teams/t1/events/${id}`)!);
      expect(later.map((e) => e.title)).toEqual(["Late practice", "Late practice", "Late practice"]);
      expect(later.map((e) => (e.startsAt as Date).toISOString())).toEqual([
        "2026-11-27T19:00:00.000Z",
        "2026-12-04T19:00:00.000Z",
        "2026-12-11T19:00:00.000Z",
      ]);
      expect((later[2]!.endsAt as Date).toISOString()).toBe("2026-12-11T20:30:00.000Z");
      expect(later[1]!.rsvps).toEqual({ player: "going" });
      expect(later.map((e) => (e.seriesWrite as { lead: boolean }).lead)).toEqual([true, false, false]);
      expect(later[0]!.series).toMatchObject({ index: 1 });
      // Just this one leaves the others alone.
      await s.call("PATCH", `/v1/teams/t1/events/${e3}`, { ...event, title: "Last one", startsAt: "2026-12-11T19:00:00Z" });
      expect(s.store.doc(`teams/t1/events/${e2}`)?.title).toBe("Late practice");
    });

    it("deletes this and following, or just this one", async () => {
      const first = (await s.call("POST", "/v1/teams/t1/events", { ...weekly, public: true })).json().id as string;
      const [e0, e1, e2, e3] = ids(first);
      expect((await s.call("DELETE", `/v1/teams/t1/events/${e3}`)).statusCode).toBe(204);
      expect((await s.call("DELETE", `/v1/teams/t1/events/${e1}?scope=following`, undefined, "player")).statusCode).toBe(403);
      expect((await s.call("DELETE", `/v1/teams/t1/events/${e1}?scope=following`)).statusCode).toBe(204);
      expect(s.store.doc(`teams/t1/events/${e0}`)).toBeDefined();
      for (const id of [e1, e2, e3]) {
        expect(s.store.doc(`teams/t1/events/${id}`)).toBeUndefined();
        expect(s.store.doc(`teams/t1/publicEvents/${id}`)).toBeUndefined();
      }
      expect((await s.call("DELETE", `/v1/teams/t1/events/${e0}?scope=sometimes`)).statusCode).toBe(400);
    });
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

    it("keeps a short note with the answer, cleaned, and drops it with the answer", async () => {
      const put = (body: object) => s.call("PUT", "/v1/teams/t1/events/e1/rsvp", body, "player");
      s.store.put("teams/t1/events/e1", { ...s.store.doc("teams/t1/events/e1"), rsvpNotes: { coach: "Bringing discs" } });
      expect((await put({ status: "going", note: "  Late\n15\u0007 min  " })).statusCode).toBe(204);
      expect(s.store.doc("teams/t1/events/e1")?.rsvpNotes).toEqual({ coach: "Bringing discs", player: "Late 15 min" });
      // Changing the answer without a note keeps it.
      await put({ status: "maybe" });
      expect(s.store.doc("teams/t1/events/e1")?.rsvpNotes).toEqual({ coach: "Bringing discs", player: "Late 15 min" });
      // An empty note removes it.
      await put({ status: "maybe", note: "   " });
      expect(s.store.doc("teams/t1/events/e1")?.rsvpNotes).toEqual({ coach: "Bringing discs" });
      await put({ status: "going", note: "Driving" });
      // Taking the answer back takes the note with it, whatever the body says.
      await put({ status: null, note: "Still here" });
      expect(s.store.doc("teams/t1/events/e1")).toMatchObject({ rsvps: { coach: "going" }, rsvpNotes: { coach: "Bringing discs" } });
      expect((await put({ status: "going", note: "x".repeat(141) })).statusCode).toBe(400);
      expect((await put({ status: "going", note: 5 })).statusCode).toBe(400);
      expect((await put({ status: "going", note: "x".repeat(140) })).statusCode).toBe(204);
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
      // An edit that doesn't send one keeps it.
      expect((await s.call("PATCH", "/v1/teams/org/events/staff", event, "coach")).statusCode).toBe(200);
      expect(s.store.doc("teams/org/events/staff")?.audience).toEqual(["staff"]);
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

  it("stamps the room's lastAt and marks it read for the sender, never storing the text on the room", async () => {
    await s.call("POST", "/v1/teams/t1/chats/general/messages", { text: "hi" }, "player");
    const room = s.store.doc("teams/t1/chats/general")!;
    expect(room.lastAt).toEqual(new Date(now));
    expect(Object.keys(room)).not.toContain("lastMessage");
    expect(s.store.doc("users/player/chatReads/t1")).toEqual({ rooms: { general: new Date(now) } });
  });

  it("marks a room read for the caller, only in rooms they can read", async () => {
    s.store.put("users/player/chatReads/t1", { rooms: { news: new Date(1) } });
    expect((await s.call("PUT", "/v1/teams/t1/chats/general/read", undefined, "player")).statusCode).toBe(204);
    expect(s.store.doc("users/player/chatReads/t1")).toEqual({ rooms: { news: new Date(1), general: new Date(now) } });
    expect((await s.call("PUT", "/v1/teams/t1/chats/coaches/read", undefined, "player")).statusCode).toBe(404);
    expect((await s.call("PUT", "/v1/teams/t1/chats/general/read", undefined, "stranger")).statusCode).toBe(404);
    expect((await s.call("PUT", "/v1/teams/t1/chats/gone/read", undefined, "player")).statusCode).toBe(404);
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
    // Any one emoji, not only the quick ones (the bubble's +).
    expect((await s.call("PUT", "/v1/teams/t1/chats/general/messages/m1/reaction", { emoji: "🐐" }, "player")).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/chats/general/messages/m1")?.reactions).toEqual({ coach: "🔥", player: "🐐" });
    expect((await s.call("PUT", "/v1/teams/t1/chats/general/messages/m1/reaction", { emoji: "ok 👍" }, "player")).statusCode).toBe(400);
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

  it("tells outsiders nothing about which messages exist", async () => {
    expect((await s.call("DELETE", "/v1/teams/t1/chats/general/messages/none", undefined, "stranger")).statusCode).toBe(404);
  });

  it("limits how fast one member sends", async () => {
    let last = 0;
    for (let i = 0; i < 61; i++) last = (await s.call("POST", "/v1/teams/t1/chats/general/messages", { text: `m${i}` }, "player")).statusCode;
    expect(last).toBe(429);
  });
});
