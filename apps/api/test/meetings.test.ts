// Meetings and voice channels against FakeStore: the `match /meetings`
// rules ported conjunct by conjunct, and the joinToken / voiceToken
// callables with a fake LiveKit signer.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import type { LiveKitGrantRequest, LiveKitSigner } from "../src/meetings/signer.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
const M = "/v1/teams/t1/meetings";

class FakeSigner implements LiveKitSigner {
  readonly url = "wss://livekit.test";
  signed: LiveKitGrantRequest[] = [];
  async sign(req: LiveKitGrantRequest) {
    this.signed.push(req);
    return `jwt:${req.room}:${req.identity}`;
  }
}

function setup(signer: LiveKitSigner | null = new FakeSigner()) {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const teams = new FakeTeamRepository();
  teams.store = store;
  const app = buildApp({ verifier: new FakeVerifier(), users, teams, store, media: new FakeMediaStorage(), now: () => now, livekit: signer ?? undefined });
  const call = async (method: "POST" | "PATCH" | "PUT" | "DELETE", url: string, body?: object, uid: string | null = "coach") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
    return { status: res.statusCode, json: () => res.json(), message: () => res.json()?.error?.message as string | undefined };
  };
  return { store, users, call, signer };
}

let s: ReturnType<typeof setup>;
const meeting = { title: "Film session", startsAt: "2026-11-20T19:00:00.000Z" };

/** A stored meeting: everyone in the player tier invited by default. */
function putMeeting(id: string, data: Record<string, unknown> = {}) {
  s.store.put(`teams/t1/meetings/${id}`, {
    title: "Film",
    startsAt: new Date(Date.UTC(2026, 10, 20, 19)),
    endsAt: null,
    notes: "",
    inviteRoles: ["player"],
    inviteUsers: [],
    requireApproval: false,
    status: "scheduled",
    rsvps: {},
    createdBy: "coach",
    ...data,
  });
}

beforeEach(() => {
  s = setup();
  s.users.records.set("coach", { name: "Casey Coach" });
  s.users.records.set("player", { name: "Pat Player" });
  s.store.put("teams/t1", {
    name: "Haze",
    ownerId: "owner",
    // phantom is in members as a coach but not in memberIds: can() holds, isMember doesn't.
    memberIds: ["owner", "coach", "helper", "player", "p2", "stats"],
    members: { owner: "owner", coach: "coach", helper: "player", player: "player", p2: "player", stats: "stats", phantom: "coach" },
    memberNames: { player: "Pat" },
    memberPerms: { helper: ["manageEvents"] },
  });
});

describe("create (allow create)", () => {
  it("stores a scheduled meeting with no answers, made by the caller", async () => {
    const res = await s.call("POST", M, {
      ...meeting,
      endsAt: "2026-11-20T20:00:00.000Z",
      inviteRoles: ["player", "coach"],
      // Admins, members invited by tier and non-members are dropped, as the app's editor does.
      inviteUsers: ["p2", "coach", "stranger", "p2"],
      requireApproval: true,
    });
    expect(res.status).toBe(201);
    const id = res.json().id;
    expect(s.store.doc(`teams/t1/meetings/${id}`)).toEqual({
      title: "Film session",
      startsAt: new Date(meeting.startsAt),
      endsAt: new Date("2026-11-20T20:00:00.000Z"),
      notes: "",
      inviteRoles: ["coach", "player"],
      inviteUsers: [],
      requireApproval: true,
      status: "scheduled",
      rsvps: {},
      createdBy: "coach",
      createdAt: new Date(now),
      updatedAt: new Date(now),
    });
  });

  it("keeps per-person invites for players not invited by tier", async () => {
    const res = await s.call("POST", M, { ...meeting, inviteRoles: [], inviteUsers: ["stats", "p2", "player"] });
    expect(s.store.doc(`teams/t1/meetings/${res.json().id}`)?.inviteUsers).toEqual(["p2", "player", "stats"]);
  });

  it("conjunct can(team, 'manageEvents'): players can't, custom roles with it can", async () => {
    expect((await s.call("POST", M, meeting, "player")).status).toBe(403);
    expect((await s.call("POST", M, meeting, "stranger")).status).toBe(403);
    expect((await s.call("POST", M, meeting, "helper")).status).toBe(201);
    expect((await s.call("POST", "/v1/teams/nope/meetings", meeting)).status).toBe(404);
  });

  it("has no isMember conjunct, as the rule doesn't", async () => {
    expect((await s.call("POST", M, meeting, "phantom")).status).toBe(201);
  });

  it("conjuncts keys().hasOnly, status == scheduled, rsvps == {}, createdBy == uid: the caller can't set them", async () => {
    expect((await s.call("POST", M, { ...meeting, status: "live" })).status).toBe(400);
    expect((await s.call("POST", M, { ...meeting, rsvps: { coach: "attending" } })).status).toBe(400);
    expect((await s.call("POST", M, { ...meeting, createdBy: "owner" })).status).toBe(400);
    expect((await s.call("POST", M, { ...meeting, extra: 1 })).status).toBe(400);
  });

  it("conjunct validMeeting: each field", async () => {
    const bad = [
      { title: "" },
      { title: "   " },
      { title: "x".repeat(101) },
      { startsAt: "whenever" },
      { endsAt: "2026-11-20T18:00:00.000Z" },
      { notes: "x".repeat(5001) },
      { notes: 5 },
      { inviteRoles: ["stats"] },
      { inviteRoles: "player" },
      { inviteUsers: Array.from({ length: 201 }, (_, i) => `u${i}`) },
      { requireApproval: "yes" },
    ];
    for (const b of bad) expect((await s.call("POST", M, { ...meeting, ...b })).status, JSON.stringify(b).slice(0, 60)).toBe(400);
  });

  it("refuses bad team ids", async () => {
    expect((await s.call("POST", "/v1/teams/__x__/meetings", meeting)).status).toBe(400);
  });
});

describe("edit (editDetails)", () => {
  beforeEach(() => putMeeting("m1", { rsvps: { player: "attending" }, status: "live" }));

  it("changes only the editable fields and updatedAt", async () => {
    expect((await s.call("PATCH", `${M}/m1`, { ...meeting, notes: "Bring cleats", inviteRoles: [], inviteUsers: ["p2"] })).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1")).toMatchObject({
      title: "Film session",
      notes: "Bring cleats",
      inviteRoles: [],
      inviteUsers: ["p2"],
      status: "live",
      rsvps: { player: "attending" },
      createdBy: "coach",
      updatedAt: new Date(now),
    });
  });

  it("conjunct isMember(team())", async () => {
    expect((await s.call("PATCH", `${M}/m1`, meeting, "phantom")).status).toBe(403);
  });

  it("conjunct can(team(), 'manageEvents')", async () => {
    expect((await s.call("PATCH", `${M}/m1`, meeting, "player")).status).toBe(403);
    expect((await s.call("PATCH", `${M}/m1`, meeting, "helper")).status).toBe(204);
  });

  it("conjunct changed().hasOnly: status, answers and the creator aren't editable", async () => {
    expect((await s.call("PATCH", `${M}/m1`, { ...meeting, status: "ended" })).status).toBe(400);
    expect((await s.call("PATCH", `${M}/m1`, { ...meeting, rsvps: {} })).status).toBe(400);
    expect((await s.call("PATCH", `${M}/m1`, { ...meeting, createdBy: "owner" })).status).toBe(400);
  });

  it("conjunct validMeeting", async () => {
    expect((await s.call("PATCH", `${M}/m1`, { ...meeting, title: "" })).status).toBe(400);
    expect((await s.call("PATCH", `${M}/m1`, { ...meeting, endsAt: "2026-11-19T00:00:00.000Z" })).status).toBe(400);
  });

  it("needs the meeting (update of a missing doc)", async () => {
    expect((await s.call("PATCH", `${M}/ghost`, meeting)).status).toBe(404);
  });
});

describe("cancel (allow delete)", () => {
  beforeEach(() => {
    putMeeting("m1");
    s.store.put("teams/t1/meetings/m1/messages/x", { authorId: "player", text: "hi" });
    s.store.put("teams/t1/meetings/m1/requests/player", { status: "pending" });
    s.store.put("teams/t1/meetings/m1/playback/current", { videoId: "v1" });
  });

  it("conjunct can(team(), 'manageEvents'), with its chat, requests and playback", async () => {
    expect((await s.call("DELETE", `${M}/m1`, undefined, "player")).status).toBe(403);
    expect(s.store.doc("teams/t1/meetings/m1")).toBeDefined();
    expect((await s.call("DELETE", `${M}/m1`, undefined, "helper")).status).toBe(204);
    expect([...s.store.docs.keys()].filter((k) => k.startsWith("teams/t1/meetings/m1"))).toEqual([]);
  });

  it("is done when it's already gone", async () => {
    expect((await s.call("DELETE", `${M}/ghost`)).status).toBe(204);
  });
});

describe("rsvp (respond)", () => {
  beforeEach(() => putMeeting("m1", { inviteRoles: [], inviteUsers: ["player"], rsvps: { coach: "attending" } }));

  it("an invitee answers for themselves only, and takes it back", async () => {
    expect((await s.call("PUT", `${M}/m1/rsvp`, { answer: "attending" }, "player")).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1")?.rsvps).toEqual({ coach: "attending", player: "attending" });
    expect((await s.call("PUT", `${M}/m1/rsvp`, { answer: null }, "player")).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1")?.rsvps).toEqual({ coach: "attending" });
  });

  it("conjunct isMember(team())", async () => {
    expect((await s.call("PUT", `${M}/m1/rsvp`, { answer: "attending" }, "phantom")).status).toBe(403);
    expect((await s.call("PUT", `${M}/m1/rsvp`, { answer: "attending" }, "stranger")).status).toBe(403);
  });

  it("conjunct invited(resource.data): by name, by tier (stats as player), or an admin", async () => {
    expect((await s.call("PUT", `${M}/m1/rsvp`, { answer: "attending" }, "p2")).status).toBe(403);
    expect((await s.call("PUT", `${M}/m1/rsvp`, { answer: "notAttending" }, "helper")).status).toBe(204);
    putMeeting("m2", { inviteRoles: ["player"] });
    expect((await s.call("PUT", `${M}/m2/rsvp`, { answer: "attending" }, "stats")).status).toBe(204);
  });

  it("conjuncts changed().hasOnly(['rsvps']) and the answer in [attending, notAttending]", async () => {
    expect((await s.call("PUT", `${M}/m1/rsvp`, { answer: "maybe" }, "player")).status).toBe(400);
    expect((await s.call("PUT", `${M}/m1/rsvp`, { answer: "attending", title: "x" }, "player")).status).toBe(400);
    expect((await s.call("PUT", `${M}/m1/rsvp`, { answer: "attending", uid: "coach" }, "player")).status).toBe(400);
  });

  it("needs the meeting", async () => {
    expect((await s.call("PUT", `${M}/ghost/rsvp`, { answer: "attending" }, "player")).status).toBe(404);
  });
});

describe("start", () => {
  beforeEach(() => putMeeting("m1"));

  it("an admin opens a scheduled meeting: live, when and by whom", async () => {
    expect((await s.call("POST", `${M}/m1/start`)).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1")).toMatchObject({ status: "live", startedAt: new Date(now), startedBy: "coach" });
  });

  it("conjunct isMember", async () => {
    expect((await s.call("POST", `${M}/m1/start`, undefined, "phantom")).status).toBe(403);
  });

  it("conjunct can(team(), 'manageEvents')", async () => {
    expect((await s.call("POST", `${M}/m1/start`, undefined, "player")).status).toBe(403);
    expect(s.store.doc("teams/t1/meetings/m1")?.status).toBe("scheduled");
  });

  it("conjunct resource.data.status == 'scheduled'", async () => {
    putMeeting("live", { status: "live" });
    putMeeting("ended", { status: "ended" });
    expect((await s.call("POST", `${M}/live/start`)).status).toBe(412);
    expect((await s.call("POST", `${M}/ended/start`)).status).toBe(412);
    expect((await s.call("POST", `${M}/ghost/start`)).status).toBe(404);
  });
});

describe("end", () => {
  beforeEach(() => {
    putMeeting("m1", { status: "live" });
    s.store.put("teams/t1/meetings/m1/playback/current", { videoId: "v1" });
  });

  it("an admin ends it for everyone, and watch together stops", async () => {
    expect((await s.call("POST", `${M}/m1/end`)).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1")).toMatchObject({ status: "ended", endedAt: new Date(now) });
    expect(s.store.doc("teams/t1/meetings/m1/playback/current")).toBeUndefined();
  });

  it("ends a scheduled meeting too (status != 'ended')", async () => {
    putMeeting("m2");
    expect((await s.call("POST", `${M}/m2/end`)).status).toBe(204);
  });

  it("conjunct isMember", async () => {
    expect((await s.call("POST", `${M}/m1/end`, undefined, "phantom")).status).toBe(403);
  });

  it("conjunct can(team(), 'manageEvents')", async () => {
    expect((await s.call("POST", `${M}/m1/end`, undefined, "player")).status).toBe(403);
  });

  it("conjunct resource.data.status != 'ended'", async () => {
    putMeeting("done", { status: "ended" });
    expect((await s.call("POST", `${M}/done/end`)).status).toBe(412);
  });
});

describe("join requests", () => {
  const R = `${M}/m1/requests`;
  beforeEach(() => putMeeting("m1", { status: "live", requireApproval: true }));

  it("an invitee asks for themselves: pending, named, now", async () => {
    expect((await s.call("PUT", `${R}/player`, undefined, "player")).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1/requests/player")).toEqual({ name: "Pat Player", status: "pending", requestedAt: new Date(now) });
  });

  it("asking again after being turned away starts over", async () => {
    s.store.put("teams/t1/meetings/m1/requests/player", { name: "Pat", status: "denied", decidedBy: "coach", decidedAt: new Date(0) });
    expect((await s.call("PUT", `${R}/player`, undefined, "player")).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1/requests/player")).toEqual({ name: "Pat Player", status: "pending", requestedAt: new Date(now) });
  });

  it("conjunct uid() == userId", async () => {
    expect((await s.call("PUT", `${R}/p2`, undefined, "player")).status).toBe(403);
  });

  it("conjunct isMember(team())", async () => {
    expect((await s.call("PUT", `${R}/phantom`, undefined, "phantom")).status).toBe(403);
  });

  it("conjunct invited(meeting())", async () => {
    putMeeting("m1", { status: "live", requireApproval: true, inviteRoles: [] });
    expect((await s.call("PUT", `${R}/player`, undefined, "player")).status).toBe(403);
  });

  it("conjunct meeting().requireApproval == true", async () => {
    putMeeting("m1", { status: "live", requireApproval: false });
    expect((await s.call("PUT", `${R}/player`, undefined, "player")).status).toBe(412);
  });

  it("conjunct meeting().status != 'ended' (asking before it starts is fine)", async () => {
    putMeeting("m1", { status: "ended", requireApproval: true });
    expect((await s.call("PUT", `${R}/player`, undefined, "player")).status).toBe(412);
    putMeeting("m1", { status: "scheduled", requireApproval: true });
    expect((await s.call("PUT", `${R}/player`, undefined, "player")).status).toBe(204);
  });

  it("conjuncts on the fields: only name, status pending and requestedAt, set by the API", async () => {
    // The body is ignored: nothing the caller sends reaches the doc.
    expect((await s.call("PUT", `${R}/player`, { status: "admitted" }, "player")).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1/requests/player")?.status).toBe("pending");
  });

  it("needs the meeting", async () => {
    expect((await s.call("PUT", `${M}/ghost/requests/player`, undefined, "player")).status).toBe(404);
  });

  describe("decide (admin update)", () => {
    beforeEach(() => s.store.put("teams/t1/meetings/m1/requests/player", { name: "Pat", status: "pending", requestedAt: new Date(0) }));

    it("lets them in or turns them away, by whom and when", async () => {
      expect((await s.call("PUT", `${R}/player/decision`, { admit: true })).status).toBe(204);
      expect(s.store.doc("teams/t1/meetings/m1/requests/player")).toEqual({
        name: "Pat",
        status: "admitted",
        requestedAt: new Date(0),
        decidedBy: "coach",
        decidedAt: new Date(now),
      });
      expect((await s.call("PUT", `${R}/player/decision`, { admit: false }, "helper")).status).toBe(204);
      expect(s.store.doc("teams/t1/meetings/m1/requests/player")).toMatchObject({ status: "denied", decidedBy: "helper" });
    });

    it("conjunct can(team(), 'manageEvents')", async () => {
      expect((await s.call("PUT", `${R}/player/decision`, { admit: true }, "player")).status).toBe(403);
      expect((await s.call("PUT", `${R}/player/decision`, { admit: true }, "p2")).status).toBe(403);
    });

    it("conjuncts affectedKeys().hasOnly and status in [admitted, denied]", async () => {
      expect((await s.call("PUT", `${R}/player/decision`, { admit: true, name: "x" })).status).toBe(400);
      expect((await s.call("PUT", `${R}/player/decision`, { status: "pending" })).status).toBe(400);
      expect((await s.call("PUT", `${R}/player/decision`, { admit: "yes" })).status).toBe(400);
    });

    it("needs the request", async () => {
      expect((await s.call("PUT", `${R}/p2/decision`, { admit: true })).status).toBe(404);
    });
  });

  describe("withdraw (delete)", () => {
    beforeEach(() => s.store.put("teams/t1/meetings/m1/requests/player", { name: "Pat", status: "pending" }));

    it("conjunct uid() == userId: the asker", async () => {
      expect((await s.call("DELETE", `${R}/player`, undefined, "player")).status).toBe(204);
      expect(s.store.doc("teams/t1/meetings/m1/requests/player")).toBeUndefined();
    });

    it("conjunct can(team(), 'manageEvents'): an admin", async () => {
      expect((await s.call("DELETE", `${R}/player`, undefined, "p2")).status).toBe(403);
      expect((await s.call("DELETE", `${R}/player`, undefined, "helper")).status).toBe(204);
    });
  });
});

describe("playback (watch together)", () => {
  const P = `${M}/m1/playback`;
  const body = { videoId: "v1", playing: true, positionMs: 1500 };
  beforeEach(() => {
    putMeeting("m1", { status: "live" });
    s.store.put("teams/t1/videos/v1", { title: "Nationals" });
  });

  it("an admin puts up a team video as the presenter, at the server's time", async () => {
    expect((await s.call("PUT", P, body)).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1/playback/current")).toEqual({
      videoId: "v1",
      playing: true,
      positionMs: 1500,
      presenterId: "coach",
      presenterName: "Casey Coach",
      updatedAt: new Date(now),
    });
    // Another admin takes over.
    expect((await s.call("PUT", P, { ...body, playing: false }, "helper")).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1/playback/current")).toMatchObject({ presenterId: "helper", playing: false });
  });

  it("conjunct can(team(), 'manageEvents')", async () => {
    expect((await s.call("PUT", P, body, "player")).status).toBe(403);
  });

  it("conjunct meeting().status == 'live'", async () => {
    putMeeting("m1", { status: "scheduled" });
    expect((await s.call("PUT", P, body)).status).toBe(412);
    putMeeting("m1", { status: "ended" });
    expect((await s.call("PUT", P, body)).status).toBe(412);
    expect((await s.call("PUT", `${M}/ghost/playback`, body)).status).toBe(404);
  });

  it("validPlayback: the video exists on this team", async () => {
    expect((await s.call("PUT", P, { ...body, videoId: "gone" })).status).toBe(404);
    expect((await s.call("PUT", P, { ...body, videoId: "a/b" })).status).toBe(400);
  });

  it("validPlayback: keys, playing bool, positionMs an int >= 0, presenter is the caller", async () => {
    expect((await s.call("PUT", P, { ...body, playing: "yes" })).status).toBe(400);
    expect((await s.call("PUT", P, { ...body, positionMs: -1 })).status).toBe(400);
    expect((await s.call("PUT", P, { ...body, positionMs: 1.5 })).status).toBe(400);
    expect((await s.call("PUT", P, { ...body, presenterId: "owner" })).status).toBe(400);
    expect((await s.call("PUT", P, { ...body, presenterName: "Owner" })).status).toBe(400);
    expect((await s.call("PUT", P, { ...body, updatedAt: "2020-01-01" })).status).toBe(400);
  });

  it("allow delete: admins stop it any time", async () => {
    s.store.put("teams/t1/meetings/m1/playback/current", { videoId: "v1" });
    expect((await s.call("DELETE", P, undefined, "player")).status).toBe(403);
    expect((await s.call("DELETE", P, undefined, "helper")).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1/playback/current")).toBeUndefined();
  });

  it("has its own bucket for the presenter's heartbeat", async () => {
    for (let i = 0; i < 40; i++) expect((await s.call("PUT", P, body)).status).toBe(204);
  });
});

describe("the call's chat (messages)", () => {
  const C = `${M}/m1/messages`;
  beforeEach(() => putMeeting("m1", { status: "live" }));

  it("people in the call send text, named and timed by the API", async () => {
    const res = await s.call("POST", C, { text: "  hello  " }, "player");
    expect(res.status).toBe(201);
    expect(s.store.doc(`teams/t1/meetings/m1/messages/${res.json().id}`)).toEqual({
      authorId: "player",
      authorName: "Pat Player",
      text: "hello",
      createdAt: new Date(now),
    });
  });

  it("conjunct notMuted()", async () => {
    s.store.put("limits/player", { mutedUntil: new Date(now + 60_000) });
    expect((await s.call("POST", C, { text: "hi" }, "player")).status).toBe(429);
  });

  it("conjunct isMember(team())", async () => {
    expect((await s.call("POST", C, { text: "hi" }, "phantom")).status).toBe(403);
  });

  it("conjunct meeting().status == 'live'", async () => {
    putMeeting("m1", { status: "scheduled" });
    expect((await s.call("POST", C, { text: "hi" }, "player")).status).toBe(412);
  });

  it("conjunct inCall(meeting()): invited, and let in when it needs approval; admins always", async () => {
    putMeeting("m1", { status: "live", inviteRoles: [] });
    expect((await s.call("POST", C, { text: "hi" }, "player")).status).toBe(403);
    putMeeting("m1", { status: "live", requireApproval: true });
    expect((await s.call("POST", C, { text: "hi" }, "player")).status).toBe(403);
    s.store.put("teams/t1/meetings/m1/requests/player", { status: "pending" });
    expect((await s.call("POST", C, { text: "hi" }, "player")).status).toBe(403);
    s.store.put("teams/t1/meetings/m1/requests/player", { status: "admitted" });
    expect((await s.call("POST", C, { text: "hi" }, "player")).status).toBe(201);
    expect((await s.call("POST", C, { text: "hi" }, "helper")).status).toBe(201);
  });

  it("conjuncts on the fields: text 1–4000, nothing else from the caller", async () => {
    expect((await s.call("POST", C, { text: "   " }, "player")).status).toBe(400);
    expect((await s.call("POST", C, { text: "x".repeat(4001) }, "player")).status).toBe(400);
    expect((await s.call("POST", C, { text: "hi", authorId: "coach" }, "player")).status).toBe(400);
    expect((await s.call("POST", C, { text: "hi", authorName: "Coach" }, "player")).status).toBe(400);
  });

  it("allow delete: authors their own, admins any", async () => {
    s.store.put("teams/t1/meetings/m1/messages/x", { authorId: "player", text: "hi" });
    expect((await s.call("DELETE", `${C}/x`, undefined, "p2")).status).toBe(403);
    expect((await s.call("DELETE", `${C}/x`, undefined, "player")).status).toBe(204);
    s.store.put("teams/t1/meetings/m1/messages/y", { authorId: "player", text: "hi" });
    expect((await s.call("DELETE", `${C}/y`, undefined, "helper")).status).toBe(204);
    expect(s.store.doc("teams/t1/meetings/m1/messages/y")).toBeUndefined();
    expect((await s.call("DELETE", `${C}/ghost`, undefined, "p2")).status).toBe(204);
  });
});

describe("join token (meetings-joinToken)", () => {
  const T = `${M}/m1/token`;
  beforeEach(() => {
    putMeeting("m1", { status: "live", inviteRoles: [], inviteUsers: ["player"] });
    s.store.put("profiles/player", { name: "Patricia", photoUrl: "https://img.test/p.jpg" });
    s.store.put("profiles/coach", { name: "Casey" });
  });

  it("signs the callable's grant: by uid, team name, photo in metadata, 6 hours, the meeting's room", async () => {
    const res = await s.call("POST", T, undefined, "player");
    expect(res.status).toBe(200);
    expect(res.json()).toEqual({ url: "wss://livekit.test", token: "jwt:t1_m1:player" });
    expect((s.signer as FakeSigner).signed).toEqual([
      { identity: "player", name: "Pat", metadata: JSON.stringify({ photoUrl: "https://img.test/p.jpg" }), ttl: "6h", room: "t1_m1", canPublish: true },
    ]);
    await s.call("POST", T, undefined, "coach");
    expect((s.signer as FakeSigner).signed[1]).toMatchObject({ identity: "coach", name: "Casey", metadata: "{}" });
  });

  it("needs a signed-in caller", async () => {
    const res = await s.call("POST", T, undefined, null);
    expect(res.status).toBe(401);
  });

  it("checks the ids as the callable does", async () => {
    const res = await s.call("POST", `${M}/a.b/token`, undefined, "player");
    expect(res.status).toBe(400);
    expect(res.message()).toBe("Unknown meeting.");
  });

  it("answers 412 when LiveKit isn't configured", async () => {
    s = setup(null);
    const res = await s.call("POST", T, undefined, "player");
    expect(res.status).toBe(412);
    expect(res.message()).toBe("Meetings aren't set up here yet.");
  });

  it("maps each refusal to the callable's code and message", async () => {
    const cases: Array<[string, () => void, number, string]> = [
      ["stranger", () => undefined, 403, "You're not on this team."],
      ["p2", () => undefined, 403, "You weren't invited to this meeting."],
      ["player", () => s.store.docs.delete("teams/t1/meetings/m1"), 403, "This meeting no longer exists."],
      ["player", () => putMeeting("m1", { status: "scheduled", inviteUsers: ["player"] }), 412, "The meeting hasn't started yet."],
      ["player", () => putMeeting("m1", { status: "ended", inviteUsers: ["player"] }), 403, "This meeting has ended."],
      ["player", () => putMeeting("m1", { status: "live", inviteUsers: ["player"], requireApproval: true }), 412, "An admin needs to let you in first."],
      ["coach", () => s.store.put("teams/t1", { ...s.store.doc("teams/t1"), deletingAt: new Date(now) }), 403, "You're not on this team."],
    ];
    for (const [uid, arrange, status, message] of cases) {
      arrange();
      const res = await s.call("POST", T, undefined, uid);
      expect([res.status, res.message()]).toEqual([status, message]);
    }
  });

  it("lets an admitted invitee and any admin into a meeting that needs approval", async () => {
    putMeeting("m1", { status: "live", inviteUsers: ["player"], requireApproval: true });
    s.store.put("teams/t1/meetings/m1/requests/player", { status: "admitted" });
    expect((await s.call("POST", T, undefined, "player")).status).toBe(200);
    expect((await s.call("POST", T, undefined, "helper")).status).toBe(200);
  });

  it("limits tokens to 30 a minute per caller", async () => {
    for (let i = 0; i < 30; i++) expect((await s.call("POST", T, undefined, "player")).status).toBe(200);
    expect((await s.call("POST", T, undefined, "player")).status).toBe(429);
  });
});

describe("voice token (meetings-voiceToken)", () => {
  const V = (room: string) => `/v1/teams/t1/voice-rooms/${room}/token`;
  beforeEach(() => {
    s.store.put("teams/t1", {
      ...s.store.doc("teams/t1"),
      memberRoles: { p2: ["handlers"] },
    });
    s.store.put("teams/t1/chats/lounge", { kind: "voice", readRoles: ["everyone"], writeRoles: ["everyone"], readUsers: [], writeUsers: [] });
    s.store.put("teams/t1/chats/handlers", { kind: "voice", readRoles: ["handlers", "coach"], writeRoles: ["handlers"], readUsers: [], writeUsers: [] });
    s.store.put("teams/t1/chats/general", { kind: "text", readRoles: ["everyone"], writeRoles: ["everyone"] });
  });

  it("readers listen and writers talk, in the channel's own room", async () => {
    const res = await s.call("POST", V("handlers"), undefined, "p2");
    expect(res.json()).toEqual({ url: "wss://livekit.test", token: "jwt:voice:t1:handlers:p2", canSpeak: true });
    const coach = await s.call("POST", V("handlers"), undefined, "coach");
    expect(coach.json().canSpeak).toBe(false);
    expect((s.signer as FakeSigner).signed[1]).toMatchObject({ identity: "coach", room: "voice:t1:handlers", canPublish: false, ttl: "6h" });
    expect((await s.call("POST", V("lounge"), undefined, "stats")).json().canSpeak).toBe(true);
  });

  it("maps each refusal to the callable's code and message", async () => {
    const cases: Array<[string, string, number, string]> = [
      ["stranger", "lounge", 403, "You're not on this team."],
      ["player", "handlers", 403, "You don't have access to this channel."],
      ["player", "ghost", 404, "This channel no longer exists."],
      ["player", "general", 412, "That's not a voice channel."],
      ["player", "a.b", 400, "Unknown channel."],
    ];
    for (const [uid, room, status, message] of cases) {
      const res = await s.call("POST", V(room), undefined, uid);
      expect([res.status, res.message()]).toEqual([status, message]);
    }
  });

  it("answers 412 when LiveKit isn't configured", async () => {
    s = setup(null);
    expect((await s.call("POST", V("lounge"), undefined, "player")).status).toBe(412);
  });
});

describe("signedIn(): every route", () => {
  it("answers 401 without a caller", async () => {
    putMeeting("m1", { status: "live" });
    const routes: Array<["POST" | "PATCH" | "PUT" | "DELETE", string, object?]> = [
      ["POST", M, meeting],
      ["PATCH", `${M}/m1`, meeting],
      ["DELETE", `${M}/m1`],
      ["PUT", `${M}/m1/rsvp`, { answer: "attending" }],
      ["POST", `${M}/m1/start`],
      ["POST", `${M}/m1/end`],
      ["PUT", `${M}/m1/requests/player`],
      ["PUT", `${M}/m1/requests/player/decision`, { admit: true }],
      ["DELETE", `${M}/m1/requests/player`],
      ["PUT", `${M}/m1/playback`, { videoId: "v1", playing: true, positionMs: 0 }],
      ["DELETE", `${M}/m1/playback`],
      ["POST", `${M}/m1/messages`, { text: "hi" }],
      ["DELETE", `${M}/m1/messages/x`],
      ["POST", `${M}/m1/token`],
      ["POST", "/v1/teams/t1/voice-rooms/lounge/token"],
    ];
    for (const [method, url, body] of routes) expect((await s.call(method, url, body, null)).status, `${method} ${url}`).toBe(401);
    expect(s.store.doc("teams/t1/meetings/m1")?.status).toBe("live");
  });
});
