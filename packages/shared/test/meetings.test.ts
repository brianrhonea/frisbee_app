// Ported from firebase/functions/test/meetings/model.test.ts and voice.test.ts
// (the callables' decisions), without the trigger and notice parts the API
// doesn't use.
import { describe, expect, it } from "vitest";
import {
  canSeeMeeting,
  type MeetingDoc,
  meetingDisplayName,
  meetingInvitees,
  meetingJoinDecision,
  meetingRoomName,
  type MeetingTeam,
  playbackPositionAt,
  saveMeetingRequestSchema,
  validMeetingId,
  voiceDecision,
  voiceInAudience,
  voiceRoomName,
  type VoiceTeam,
} from "../src/meetings.js";

const team: MeetingTeam = {
  name: "Rockets",
  members: { o: "owner", c: "coach", k: "captain", p1: "player", p2: "player", s: "stats" },
  memberNames: { p1: "Pat" },
};

const adminsOnly: MeetingDoc = { inviteRoles: [], inviteUsers: ["p1"], status: "scheduled" };
const everyone: MeetingDoc = { inviteRoles: ["player"], inviteUsers: [], status: "live" };

describe("canSeeMeeting", () => {
  it("admins always; others by role or by name", () => {
    for (const uid of ["o", "c", "k"]) expect(canSeeMeeting(team, adminsOnly, uid)).toBe(true);
    expect(canSeeMeeting(team, adminsOnly, "p1")).toBe(true);
    expect(canSeeMeeting(team, adminsOnly, "p2")).toBe(false);
    expect(canSeeMeeting(team, everyone, "p2")).toBe(true);
  });

  it("members whose custom roles grant manageEvents see every meeting", () => {
    const roled: MeetingTeam = { ...team, memberPerms: { p2: ["manageEvents"], s: ["moderate"] } };
    expect(canSeeMeeting(roled, adminsOnly, "p2")).toBe(true);
    expect(canSeeMeeting(roled, adminsOnly, "s")).toBe(false);
    // Permissions don't outlive membership.
    expect(canSeeMeeting({ ...roled, memberPerms: { gone: ["manageEvents"] } }, adminsOnly, "gone")).toBe(false);
  });

  it("treats a legacy stats member as a player, and outsiders see nothing", () => {
    expect(canSeeMeeting(team, everyone, "s")).toBe(true);
    expect(canSeeMeeting(team, adminsOnly, "s")).toBe(false);
    expect(canSeeMeeting(team, everyone, "stranger")).toBe(false);
    // A uid that's an Object.prototype key is no member.
    expect(canSeeMeeting(team, everyone, "constructor")).toBe(false);
  });

  it("lists invitees", () => {
    expect(meetingInvitees(team, adminsOnly).sort()).toEqual(["c", "k", "o", "p1"]);
  });
});

describe("meetingJoinDecision", () => {
  const live: MeetingDoc = { ...adminsOnly, status: "live" };

  it("lets invitees into a live meeting", () => {
    expect(meetingJoinDecision({ team, meeting: live, uid: "p1" })).toBe("ok");
  });

  it("keeps out outsiders, the uninvited and everyone outside live", () => {
    expect(meetingJoinDecision({ team, meeting: live, uid: "stranger" })).toBe("notMember");
    expect(meetingJoinDecision({ team: { ...team, deletingAt: 1 }, meeting: live, uid: "o" })).toBe("notMember");
    expect(meetingJoinDecision({ team, meeting: undefined, uid: "o" })).toBe("missing");
    expect(meetingJoinDecision({ team, meeting: live, uid: "p2" })).toBe("notInvited");
    expect(meetingJoinDecision({ team, meeting: adminsOnly, uid: "o" })).toBe("notStarted");
    expect(meetingJoinDecision({ team, meeting: { ...live, status: "ended" }, uid: "o" })).toBe("ended");
  });

  it("needs an admitted request when approval is on, except for admins", () => {
    const gated: MeetingDoc = { ...live, requireApproval: true };
    expect(meetingJoinDecision({ team, meeting: gated, uid: "p1" })).toBe("needsApproval");
    expect(meetingJoinDecision({ team, meeting: gated, uid: "p1", request: { status: "pending" } })).toBe("needsApproval");
    expect(meetingJoinDecision({ team, meeting: gated, uid: "p1", request: { status: "denied" } })).toBe("needsApproval");
    expect(meetingJoinDecision({ team, meeting: gated, uid: "p1", request: { status: "admitted" } })).toBe("ok");
    expect(meetingJoinDecision({ team, meeting: gated, uid: "c" })).toBe("ok");
  });
});

describe("naming", () => {
  it("prefers the team's name for a member, then their profile", () => {
    expect(meetingDisplayName(team, "p1", "Patricia")).toBe("Pat");
    expect(meetingDisplayName(team, "p2", "Sam")).toBe("Sam");
    expect(meetingDisplayName(team, "p2", undefined)).toBe("Member");
  });

  it("rooms are per meeting", () => {
    expect(meetingRoomName("t1", "m1")).toBe("t1_m1");
  });

  it("checks ids as the callables do", () => {
    expect(validMeetingId("abc_DEF-1")).toBe(true);
    for (const bad of ["", "a/b", "a.b", "x".repeat(129), 5, null]) expect(validMeetingId(bad)).toBe(false);
  });
});

const vteam: VoiceTeam = {
  members: { o: "owner", c: "coach", p1: "player", p2: "player", s: "stats" },
  memberRoles: { p1: ["handlers"] },
};
const lounge = { kind: "voice", readRoles: ["everyone"], writeRoles: ["everyone"] };
const handlers = { kind: "voice", readRoles: ["handlers", "coach"], writeRoles: ["handlers"] };

describe("voiceInAudience", () => {
  it("matches everyone, tiers, custom roles and names", () => {
    expect(voiceInAudience(vteam, "p2", ["everyone"])).toBe(true);
    expect(voiceInAudience(vteam, "c", ["coach"])).toBe(true);
    expect(voiceInAudience(vteam, "s", ["player"])).toBe(true);
    expect(voiceInAudience(vteam, "p1", ["handlers"])).toBe(true);
    expect(voiceInAudience(vteam, "p2", ["handlers"])).toBe(false);
    expect(voiceInAudience(vteam, "p2", [], ["p2"])).toBe(true);
    expect(voiceInAudience(vteam, "o", [])).toBe(true);
    expect(voiceInAudience(vteam, "stranger", ["everyone"])).toBe(false);
  });
});

describe("voiceDecision", () => {
  it("lets readers listen and writers talk", () => {
    expect(voiceDecision(vteam, lounge, "p2")).toEqual({ ok: true, canSpeak: true });
    expect(voiceDecision(vteam, handlers, "p1")).toEqual({ ok: true, canSpeak: true });
    expect(voiceDecision(vteam, handlers, "c")).toEqual({ ok: true, canSpeak: false });
  });

  it("turns away outsiders, text rooms and missing channels", () => {
    expect(voiceDecision(vteam, handlers, "p2")).toMatchObject({ ok: false, code: "permission-denied" });
    expect(voiceDecision(vteam, lounge, "stranger")).toMatchObject({ ok: false, code: "permission-denied" });
    expect(voiceDecision(undefined, lounge, "p1")).toMatchObject({ ok: false });
    expect(voiceDecision({ ...vteam, deletingAt: 1 }, lounge, "p1")).toMatchObject({ ok: false });
    expect(voiceDecision(vteam, undefined, "p1")).toMatchObject({ ok: false, code: "not-found" });
    expect(voiceDecision(vteam, { ...lounge, kind: "text" }, "p1")).toMatchObject({ ok: false, code: "failed-precondition" });
    expect(voiceDecision(vteam, { readRoles: ["everyone"] }, "p1")).toMatchObject({ ok: false });
  });

  it("names rooms apart from meetings", () => {
    expect(voiceRoomName("t1", "voice-lounge")).toBe("voice:t1:voice-lounge");
  });
});

describe("playbackPositionAt", () => {
  const at = "2026-11-14T12:00:00.000Z";
  const t = Date.parse(at);
  it("adds the time since the change while playing", () => {
    expect(playbackPositionAt({ playing: true, positionMs: 5000, updatedAt: at }, t + 2000)).toBe(7000);
    expect(playbackPositionAt({ playing: false, positionMs: 5000, updatedAt: at }, t + 2000)).toBe(5000);
  });
  it("ignores pending writes and clocks behind the server", () => {
    expect(playbackPositionAt({ playing: true, positionMs: 5000, updatedAt: null }, t)).toBe(5000);
    expect(playbackPositionAt({ playing: true, positionMs: 5000, updatedAt: at }, t - 1000)).toBe(5000);
  });
});

describe("saveMeetingRequestSchema", () => {
  const base = { title: " Film ", startsAt: "2026-11-20T19:00:00Z" };
  it("fills the defaults and trims the title", () => {
    expect(saveMeetingRequestSchema.parse(base)).toEqual({
      title: "Film",
      startsAt: base.startsAt,
      endsAt: null,
      notes: "",
      inviteRoles: [],
      inviteUsers: [],
      requireApproval: false,
    });
  });
  it("refuses what validMeeting refuses", () => {
    expect(saveMeetingRequestSchema.safeParse({ ...base, title: "  " }).success).toBe(false);
    expect(saveMeetingRequestSchema.safeParse({ ...base, title: "x".repeat(101) }).success).toBe(false);
    expect(saveMeetingRequestSchema.safeParse({ ...base, startsAt: "soon" }).success).toBe(false);
    expect(saveMeetingRequestSchema.safeParse({ ...base, endsAt: "2026-11-20T18:00:00Z" }).success).toBe(false);
    expect(saveMeetingRequestSchema.safeParse({ ...base, notes: "x".repeat(5001) }).success).toBe(false);
    expect(saveMeetingRequestSchema.safeParse({ ...base, inviteRoles: ["stats"] }).success).toBe(false);
    expect(saveMeetingRequestSchema.safeParse({ ...base, inviteUsers: Array.from({ length: 201 }, (_, i) => `u${i}`) }).success).toBe(false);
    expect(saveMeetingRequestSchema.safeParse({ ...base, requireApproval: "yes" }).success).toBe(false);
    expect(saveMeetingRequestSchema.safeParse({ ...base, status: "live" }).success).toBe(false);
  });
});
