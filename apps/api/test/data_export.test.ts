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
  async pollVotes(teamId: string, uid: string, limit: number) {
    const docs = this.where((d, s) => {
      const poll = d.data.poll as Data | undefined;
      return s.length === 6 && s[0] === "teams" && s[1] === teamId && s[2] === "chats" && ((poll?.voterIds as string[]) ?? []).includes(uid);
    }, limit);
    return docs.map((d) => {
      const poll = d.data.poll as Data;
      return { ...d, data: { poll: { question: poll.question, options: poll.options, votes: { [uid]: (poll.votes as Data)[uid] } } } };
    });
  }
  async reportsBy(uid: string, limit: number) {
    return this.where((d, s) => s.length === 2 && s[0] === "reports" && d.data.reporterId === uid, limit);
  }
  async likedPosts(uid: string, limit: number) {
    return this.where((d, s) => s.length === 2 && s[0] === "posts" && ((d.data.likedBy as string[]) ?? []).includes(uid), limit).map((d) => ({ ...d, data: {} }));
  }
  async calendarsOf(uid: string, limit: number) {
    return this.where((d, s) => s.length === 2 && s[0] === "calendars" && ((d.data.memberIds as string[]) ?? []).includes(uid), limit);
  }
  async usernamesOf(uid: string, limit: number) {
    return this.where((d, s) => s.length === 2 && s[0] === "usernames" && d.data.uid === uid, limit);
  }
  async followRequestsSent(uid: string, limit: number) {
    const owners = this.where((d, s) => s.length === 2 && s[0] === "profiles" && d.data.private === true, 10_000);
    return owners
      .flatMap((o) => this.where((d) => d.path === `${o.path}/followRequests/${uid}`, 1).map((r) => ({ ...r, owner: o.data })))
      .slice(0, limit + 1);
  }
  async signupsOf(uid: string, limit: number) {
    const ts = this.where((d, s) => s.length === 2 && s[0] === "tournaments", 10_000);
    return ts.flatMap((t) => this.where((d) => d.path === `${t.path}/signups/${uid}`, 1).map((r) => ({ ...r, tournament: t.data }))).slice(0, limit + 1);
  }
  async joinRequestsOf(uid: string, limit: number) {
    // Groups that approve who joins and teams that allow requests, as the Firestore queries find them.
    const hosts = this.where((d, s) => {
      if (s.length !== 2 || s[0] !== "teams") return false;
      const group = d.data.kind === "community" || d.data.kind === "organization";
      return group ? d.data.requiresApproval === true : d.data.allowJoinRequests === true;
    }, 10_000);
    return hosts
      .flatMap((h) => this.where((d) => d.path === `${h.path}/joinRequests/${uid}`, 1).map((r) => ({ ...r, team: h.data })))
      .slice(0, limit + 1);
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
  s.store.put("teams/t1/roster/r1", { name: "Mia", number: 7, position: "cutter", userId: "me", line: "d" });
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

  it("has what they own beyond content: liked posts, follow requests both ways, sign-ups, calendars, invites and usernames (#27)", async () => {
    const at = new Date(now - 3600_000);
    s.store.put("posts/lp1", { authorId: "you", body: "Liked it", likedBy: ["me", "you"] });
    s.store.put("posts/lp2", { authorId: "you", body: "Not liked", likedBy: ["you"] });
    s.store.put("profiles/you", { name: "Yan", private: true });
    s.store.put("profiles/you/followRequests/me", { name: "Mia", username: "mia", createdAt: at });
    s.store.put("profiles/me", { name: "Mia", private: true });
    s.store.put("profiles/me/followRequests/zed", { name: "Zed", username: null, createdAt: at });
    s.store.put("tournaments/t9", { name: "Fall Open" });
    s.store.put("tournaments/t9/signups/me", { name: "Mia", divisionId: "d1", skill: 3, gender: "wmp", status: "accepted", createdAt: at });
    s.store.put("tournaments/t9/signups/you", { name: "Yan", divisionId: "d1", skill: 2, status: "applied" });
    s.store.put("calendars/cal1", { ownerId: "me", name: "Mine", members: { me: "owner" }, memberIds: ["me"] });
    s.store.put("calendars/cal2", { ownerId: "you", name: "Yan's", members: { you: "owner", me: "edit" }, memberIds: ["you", "me"] });
    s.store.put("calendars/cal3", { ownerId: "you", name: "Not mine", members: { you: "owner" }, memberIds: ["you"] });
    s.store.put("users/me/calendarInvites/cal4", { calendarId: "cal4", role: "view", fromId: "you" });
    s.store.put("usernames/mia", { uid: "me" });
    s.store.put("usernames/yan", { uid: "you" });
    const data = (await s.get()).json() as DataExport;
    expect(data.likedPosts.items).toEqual([{ postId: "lp1" }]);
    expect(data.followRequests.sent.items).toEqual([{ ownerId: "you", ownerName: "Yan", createdAt: at.toISOString() }]);
    expect(data.followRequests.received.items).toEqual([{ requesterId: "zed", name: "Zed", username: null, createdAt: at.toISOString() }]);
    expect(data.signups.items).toEqual([
      { tournamentId: "t9", tournamentName: "Fall Open", name: "Mia", divisionId: "d1", skill: 3, gender: "wmp", status: "accepted", createdAt: at.toISOString() },
    ]);
    expect(data.calendars.items).toEqual([
      { id: "cal1", name: "Mine", role: "owner" },
      { id: "cal2", name: "Yan's", role: "edit" },
    ]);
    expect(data.calendarInvites.items).toEqual([{ id: "cal4", calendarId: "cal4", role: "view", fromId: "you" }]);
    expect(data.usernames.items).toEqual([{ username: "mia" }]);
  });

  it("leaves the age-refusal record out of the export (D-AR)", async () => {
    seed();
    s.store.put("ageRefusals/me", { ciphertext: "sealed-birth-date", key: "k", refusedAt: new Date(now) });
    const res = await s.get();
    const data = res.json() as Record<string, unknown>;
    expect(Object.keys(data).some((k) => /refusal/i.test(k))).toBe(false);
    expect(res.body).not.toContain("sealed-birth-date");
    expect(res.body).not.toMatch(/ageRefusals/);
  });

  it("has their notes, clips and comments on team videos (F4, F5)", async () => {
    s.store.put("teams/t1/videos/v1/comments/n1", { authorId: "me", authorName: "Mia", body: "Watch the mark", atMs: 83_000, endMs: 90_000 });
    s.store.put("teams/t1/videos/v1/comments/c3", { authorId: "me", authorName: "Mia", body: "Great game" });
    s.store.put("teams/t1/videos/v1/comments/c4", { authorId: "you", body: "Not mine" });
    const data = (await s.get()).json() as DataExport;
    expect(data.comments.items).toEqual([
      { id: "c3", teamId: "t1", videoId: "v1", body: "Great game" },
      { id: "n1", teamId: "t1", videoId: "v1", atMs: 83_000, endMs: 90_000, body: "Watch the mark" },
    ]);
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
    expect(data.rosterSpots.items).toEqual([{ teamId: "t1", name: "Mia", number: 7, position: "cutter", line: "d" }]);
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

  it("has their chat poll votes (F33) and polls they posted, never others' votes", async () => {
    seed();
    const poll = (votes: Record<string, number[]>) => ({ question: "Which day?", options: ["Sat", "Sun"], multiple: true, votes, voterIds: Object.keys(votes) });
    s.store.put("teams/t1/chats/general/messages/p1", { authorId: "you", authorName: "Yan", text: "", attachments: [], poll: poll({ me: [0, 1], you: [1] }) });
    s.store.put("teams/t1/chats/general/messages/p2", { authorId: "you", text: "", attachments: [], poll: poll({ you: [0] }) });
    s.store.put("teams/t1/chats/general/messages/p3", { authorId: "me", text: "", attachments: [], poll: poll({ you: [0] }) });
    const data = (await s.get()).json() as DataExport;
    expect(data.pollVotes).toEqual({
      items: [{ teamId: "t1", teamName: "The Haze", roomId: "general", messageId: "p1", question: "Which day?", options: ["Sat", "Sun"], picked: [0, 1] }],
      truncated: false,
    });
    expect(data.messages.items.find((m) => m.id === "p3")).toMatchObject({ text: "", poll: { question: "Which day?", options: ["Sat", "Sun"] } });
    expect(JSON.stringify(data.messages.items.find((m) => m.id === "p3"))).not.toContain("you");
  });

  it("has their requests to join groups and teams (F26), never anyone else's", async () => {
    const at = new Date(now - 60_000);
    s.store.put("teams/t3", { name: "Rival", allowJoinRequests: true, memberIds: ["you"] });
    s.store.put("teams/t3/joinRequests/me", { name: "Mia", createdAt: at });
    s.store.put("teams/t3/joinRequests/you", { name: "Yan", createdAt: at });
    s.store.put("teams/g1", { name: "Pickup", kind: "community", requiresApproval: true, memberIds: ["you"] });
    s.store.put("teams/g1/joinRequests/me", { name: "Mia" });
    const data = (await s.get()).json() as DataExport;
    expect(data.joinRequests).toEqual({
      items: [
        { teamId: "g1", teamName: "Pickup", kind: "community", name: "Mia" },
        { teamId: "t3", teamName: "Rival", kind: "team", name: "Mia", createdAt: at.toISOString() },
      ],
      truncated: false,
    });
  });

  it("an empty account still downloads, with empty sections", async () => {
    const data = (await s.get("new")).json() as DataExport;
    expect(data.profile).toBeNull();
    expect(data.joinRequests).toEqual({ items: [], truncated: false });
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

describe("blocks and reports in the export", () => {
  it("lists who you blocked and what you reported, not who blocked you or the reported content", async () => {
    s.store.put("users/me/blocks/you", { mine: true, name: "Yan", blockedAt: new Date(now) });
    s.store.put("users/me/blocks/zed", { mine: false });
    s.store.put("reports/r1", {
      reporterId: "me",
      target: { kind: "post", postId: "p2" },
      reason: "spam",
      details: "Bot",
      status: "open",
      snapshot: { text: "Not mine", images: [] },
      createdAt: new Date(now),
    });
    s.store.put("reports/r2", { reporterId: "you", target: { kind: "user", uid: "me" }, reason: "spam", status: "open" });
    const data = (await s.get()).json();
    expect(data.blocks.items).toEqual([{ uid: "you", name: "Yan", blockedAt: new Date(now).toISOString() }]);
    expect(data.reports.items).toEqual([
      { id: "r1", target: { kind: "post", postId: "p2" }, reason: "spam", details: "Bot", status: "open", createdAt: new Date(now).toISOString() },
    ]);
    expect(JSON.stringify(data)).not.toContain("Not mine\"}");
  });
});
