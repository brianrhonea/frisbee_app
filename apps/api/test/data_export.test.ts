// "Download your data" (GET /v1/me/export) against FakeStore: the caller's
// own data, field by field where others are involved, and once per ten
// minutes.
import type { DataExport } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { ExportRepository, PathDoc } from "../src/export/repository.js";
import { messagePlace } from "../src/export/service.js";
import type { Data } from "../src/store.js";
import { FakeCipher, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier, seedBirthDate } from "./fakes.js";

const minute = 60_000;

/** ExportRepository over FakeStore's documents, as the Firestore queries would answer. */
class FakeExportRepository implements ExportRepository {
  constructor(private readonly store: FakeStore) {}

  private iso(v: unknown): unknown {
    if (v instanceof Date) return v.toISOString();
    if (Array.isArray(v)) return v.map((x) => this.iso(x));
    if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, this.iso(x)]));
    return v;
  }
  private all(): PathDoc[] {
    return [...this.store.docs.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([path, data]) => ({ id: path.split("/").pop()!, path, data: this.iso(data) as Data }));
  }
  private where(test: (d: PathDoc, s: string[]) => boolean, limit: number) {
    return this.all()
      .filter((d) => test(d, d.path.split("/")))
      .slice(0, limit + 1);
  }

  async own(path: string) {
    const d = this.store.doc(path);
    return d ? (this.iso(d) as Data) : null;
  }
  async ownCollection(path: string, limit: number) {
    const n = path.split("/").length + 1;
    return this.where((d, s) => d.path.startsWith(`${path}/`) && s.length === n, limit);
  }
  async authored(group: string, uid: string, limit: number) {
    return this.where((d, s) => s[s.length - 2] === group && d.data.authorId === uid, limit);
  }
  async conversationsOf(uid: string, limit: number) {
    return this.where((d, s) => s.length === 2 && s[0] === "conversations" && (d.data.participants as string[]).includes(uid), limit);
  }
  async teamsOf(uid: string, limit: number) {
    return this.where((d, s) => s.length === 2 && s[0] === "teams" && ((d.data.memberIds as string[]) ?? []).includes(uid), limit);
  }
  async answers(teamId: string, kind: string, uid: string, fields: readonly string[], responseFields: readonly string[], limit: number) {
    const docs = await this.ownCollection(`teams/${teamId}/${kind}`, limit);
    return docs.map((d) => {
      const data: Data = {};
      for (const f of fields) if (f in d.data) data[f] = d.data[f];
      for (const f of responseFields) {
        const m = d.data[f] as Data | undefined;
        if (m && uid in m) data[f] = { [uid]: m[uid] };
      }
      return { ...d, data };
    });
  }
  async rosterSpots(uid: string, limit: number) {
    return this.where((d, s) => s[s.length - 2] === "roster" && d.data.userId === uid, limit);
  }
}

let now = Date.UTC(2026, 10, 20, 12);

function setup(withPersonal = true) {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const cipher = new FakeCipher();
  const app = buildApp({
    verifier: new FakeVerifier(),
    users,
    teams: new FakeTeamRepository(),
    store,
    exports: new FakeExportRepository(store),
    ...(withPersonal && { personal: cipher }),
    now: () => now,
  });
  const get = (uid = "me") =>
    app.inject({ method: "GET", url: "/v1/me/export", headers: { authorization: `Bearer token:${uid}:Me` } });
  return { store, users, cipher, app, get };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  now = Date.UTC(2026, 10, 20, 12);
  s = setup();
});

function seed() {
  const at = new Date(now - 3600_000);
  s.users.records.set("me", { name: "Mia", email: "mia@x.test", createdAt: "2026-01-02T00:00:00.000Z" });
  s.store.put("users/me", { messagePolicy: "followers", readReceipts: true, fcmToken: "secret-token" });
  s.store.put("users/me/settings/notifications", { categories: { chat: true } });
  s.store.put("users/me/follows/user_you", { type: "user", targetId: "you", createdAt: at });
  s.store.put("users/me/events/m1", { title: "Gym", startsAt: at });
  s.store.put("users/me/devices/fid1", { token: "push-token" });
  s.store.put("profiles/me", { name: "Mia", username: "mia", keywords: ["mia"], stats: { goals: 3 } });
  // Mine, and someone else's.
  s.store.put("posts/p1", { authorId: "me", body: "Hello", likedBy: ["you"], repostedBy: ["you"], createdAt: at });
  s.store.put("posts/p2", { authorId: "you", body: "Not mine" });
  s.store.put("teams/t1/posts/tp1", { authorId: "me", title: "Practice moved", public: true });
  s.store.put("posts/p2/comments/c1", { authorId: "me", body: "Nice", createdAt: at });
  s.store.put("posts/p2/comments/c2", { authorId: "you", body: "Thanks" });
  s.store.put("conversations/me_you", {
    participants: ["me", "you"],
    names: { me: "Mia", you: "Yan" },
    lastMessage: "Your secret plan",
    lastSenderId: "you",
  });
  s.store.put("conversations/me_you/messages/m1", { authorId: "me", text: "Hi Yan", createdAt: at, replyTo: { id: "m0", text: "Yan's words" } });
  s.store.put("conversations/me_you/messages/m2", { authorId: "you", text: "Yan's reply" });
  s.store.put("teams/t1/chats/general/messages/c1", { authorId: "me", text: "See you there", attachments: [{ name: "map.png", path: "x/map.png", contentType: "image/png", size: 10, uploadedBy: "me" }] });
  s.store.put("teams/t1", {
    name: "The Haze",
    members: { me: "captain", you: "owner" },
    memberIds: ["me", "you"],
    memberNames: { me: "Mia", you: "Yan" },
    memberRoles: { me: ["r1"], you: ["r2"] },
    memberPerms: { me: ["manageEvents"], you: ["manageMembers"] },
    roles: { r1: { name: "Scheduler" }, r2: { name: "Treasurer" } },
    statKeepers: ["you"],
  });
  s.store.put("teams/t2", { name: "Not mine", members: { you: "owner" }, memberIds: ["you"] });
  s.store.put("teams/t1/events/e1", {
    title: "Practice",
    startsAt: at,
    rsvps: { me: "going", you: "maybe" },
    rsvpNotes: { me: "Late", you: "Yan's note" },
    votes: { you: ["a"] },
  });
  s.store.put("teams/t1/events/e2", { title: "Not answered", rsvps: { you: "going" } });
  s.store.put("teams/t1/meetings/mt1", { title: "Film", rsvps: { me: "going" } });
  s.store.put("teams/t1/roster/r1", { name: "Mia", number: 7, position: "cutter", userId: "me" });
  s.store.put("teams/t1/roster/r2", { name: "Yan", number: 8, userId: "you" });
}

describe("GET /v1/me/export", () => {
  it("is a JSON file to download, never cached", async () => {
    seed();
    const res = await s.get();
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-disposition"]).toBe('attachment; filename="stall10-data-2026-11-20.json"');
    expect(res.headers["content-type"]).toContain("application/json");
    expect(res.headers["cache-control"]).toBe("private, no-store");
    const data = res.json() as DataExport;
    expect(data).toMatchObject({ format: "stall10-data-export", version: 1, uid: "me", exportedAt: new Date(now).toISOString() });
  });

  it("holds the caller's account, profile, settings, follows and own events, without secrets or search keys", async () => {
    seed();
    const data = (await s.get()).json() as DataExport;
    expect(data.account).toEqual({ email: "mia@x.test", name: "Mia", createdAt: "2026-01-02T00:00:00.000Z" });
    expect(data.user).toEqual({ messagePolicy: "followers", readReceipts: true });
    expect(data.profile).toEqual({ name: "Mia", username: "mia", stats: { goals: 3 } });
    expect(data.notificationSettings).toEqual({ categories: { chat: true } });
    expect(data.follows.items).toEqual([{ id: "user_you", type: "user", targetId: "you", createdAt: new Date(now - 3600_000).toISOString() }]);
    expect(data.personalEvents.items.map((e) => e.title)).toEqual(["Gym"]);
    expect(JSON.stringify(data)).not.toContain("push-token");
    expect(JSON.stringify(data)).not.toContain("secret-token");
  });

  it("has their posts (profile and team) without who liked them, and their comments", async () => {
    seed();
    const data = (await s.get()).json() as DataExport;
    expect(data.posts.items).toEqual([
      { id: "p1", authorId: "me", body: "Hello", createdAt: new Date(now - 3600_000).toISOString() },
      { id: "tp1", teamId: "t1", authorId: "me", title: "Practice moved", public: true },
    ]);
    expect(data.comments.items).toEqual([{ id: "c1", postId: "p2", body: "Nice", createdAt: new Date(now - 3600_000).toISOString() }]);
  });

  it("has the messages they sent, never anyone else's, nor a conversation's last message", async () => {
    seed();
    const data = (await s.get()).json() as DataExport;
    expect(data.messages.items).toEqual([
      {
        id: "m1",
        place: { kind: "direct", conversationId: "me_you" },
        text: "Hi Yan",
        createdAt: new Date(now - 3600_000).toISOString(),
        replyToId: "m0",
      },
      {
        id: "c1",
        place: { kind: "teamChat", teamId: "t1", roomId: "general" },
        text: "See you there",
        attachments: [{ name: "map.png", path: "x/map.png", contentType: "image/png", size: 10 }],
      },
    ]);
    expect(data.conversations.items).toEqual([
      { id: "me_you", kind: "direct", participants: [{ uid: "me", name: "Mia" }, { uid: "you", name: "Yan" }] },
    ]);
    const text = JSON.stringify(data);
    for (const theirs of ["Your secret plan", "Yan's reply", "Yan's words", "Yan's note", "Treasurer", "Thanks", "Not mine"]) {
      expect(text).not.toContain(theirs);
    }
  });

  it("has their teams with their own role, their answers and roster spots only", async () => {
    seed();
    const data = (await s.get()).json() as DataExport;
    expect(data.teams.items).toEqual([
      { id: "t1", name: "The Haze", kind: "team", tier: "captain", roles: ["Scheduler"], permissions: ["manageEvents"], statKeeper: false },
    ]);
    expect(data.responses.items).toEqual([
      { teamId: "t1", teamName: "The Haze", kind: "event", id: "e1", title: "Practice", startsAt: new Date(now - 3600_000).toISOString(), rsvp: "going", note: "Late" },
      { teamId: "t1", teamName: "The Haze", kind: "meeting", id: "mt1", title: "Film", rsvp: "going" },
    ]);
    expect(data.rosterSpots.items).toEqual([{ teamId: "t1", name: "Mia", number: 7, position: "cutter" }]);
  });

  it("decrypts their personal details; without the key they're marked unavailable", async () => {
    seed();
    await seedBirthDate(s.store, s.cipher, "me", "1999-05-06");
    expect(((await s.get()).json() as DataExport).personalDetails).toEqual({ birthDate: "1999-05-06" });

    const other = setup(false);
    other.store.put("personalDetails/me", { ciphertext: "x", key: "y", format: 1 });
    expect(((await other.get()).json() as DataExport).personalDetails).toBe("unavailable");
    const none = setup(false);
    expect(((await none.get()).json() as DataExport).personalDetails).toBeNull();
  });

  it("an empty account still downloads, with empty sections", async () => {
    const data = (await s.get("new")).json() as DataExport;
    expect(data.profile).toBeNull();
    expect(data.posts).toEqual({ items: [], truncated: false });
    expect(data.teams).toEqual({ items: [], truncated: false });
  });

  it("once every 10 minutes per person, kept in limits/{uid}", async () => {
    expect((await s.get()).statusCode).toBe(200);
    expect(s.store.doc("limits/me")?.exportedAt).toEqual(new Date(now));
    now += 4 * minute;
    const again = await s.get();
    expect(again.statusCode).toBe(429);
    expect((again.json() as { error: { message: string } }).error.message).toBe(
      "You can download your data once every 10 minutes. Try again in 6 minutes.",
    );
    // Someone else isn't held up.
    expect((await s.get("other")).statusCode).toBe(200);
    now += 6 * minute;
    expect((await s.get()).statusCode).toBe(200);
  });

  it("keeps the mute counters already in limits/{uid}", async () => {
    s.store.put("limits/me", { counts: { post: { n: 3 } } });
    expect((await s.get()).statusCode).toBe(200);
    expect(s.store.doc("limits/me")).toEqual({ counts: { post: { n: 3 } }, exportedAt: new Date(now) });
  });

  it("needs a signed-in caller", async () => {
    const res = await s.app.inject({ method: "GET", url: "/v1/me/export" });
    expect(res.statusCode).toBe(401);
  });
});

describe("messagePlace", () => {
  it("names where a message lives by its path", () => {
    expect(messagePlace("conversations/a_b/messages/m")).toEqual({ kind: "direct", conversationId: "a_b" });
    expect(messagePlace("teams/t/chats/r/messages/m")).toEqual({ kind: "teamChat", teamId: "t", roomId: "r" });
    expect(messagePlace("teams/t/meetings/x/messages/m")).toEqual({ kind: "meeting", teamId: "t", meetingId: "x" });
    expect(messagePlace("elsewhere/x/messages/m")).toEqual({ kind: "other", path: "elsewhere/x/messages/m" });
  });
});
