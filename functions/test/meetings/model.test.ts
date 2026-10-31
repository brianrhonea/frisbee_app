import { describe, expect, it } from "vitest";

import {
  canSee,
  displayName,
  invitees,
  joinDecision,
  type MeetingDoc,
  meetingChange,
  type MeetingTeam,
  roomName,
  startedRecipients,
} from "../../src/meetings/model";
import { meetingStartedNotice } from "../../src/notifications/model";

const team: MeetingTeam = {
  name: "Rockets",
  members: { o: "owner", c: "coach", k: "captain", p1: "player", p2: "player", s: "stats" },
  memberNames: { p1: "Pat" },
};

const adminsOnly: MeetingDoc = { inviteRoles: [], inviteUsers: ["p1"], status: "scheduled" };
const everyone: MeetingDoc = { inviteRoles: ["player"], inviteUsers: [], status: "live" };

describe("canSee", () => {
  it("admins always; others by role or by name", () => {
    for (const uid of ["o", "c", "k"]) expect(canSee(team, adminsOnly, uid)).toBe(true);
    expect(canSee(team, adminsOnly, "p1")).toBe(true);
    expect(canSee(team, adminsOnly, "p2")).toBe(false);
    expect(canSee(team, everyone, "p2")).toBe(true);
  });

  it("treats a legacy stats member as a player, and outsiders see nothing", () => {
    expect(canSee(team, everyone, "s")).toBe(true);
    expect(canSee(team, adminsOnly, "s")).toBe(false);
    expect(canSee(team, everyone, "stranger")).toBe(false);
  });

  it("lists invitees", () => {
    expect(invitees(team, adminsOnly).sort()).toEqual(["c", "k", "o", "p1"]);
  });
});

describe("joinDecision", () => {
  const live: MeetingDoc = { ...adminsOnly, status: "live" };

  it("lets invitees into a live meeting", () => {
    expect(joinDecision({ team, meeting: live, uid: "p1" })).toBe("ok");
  });

  it("keeps out outsiders, the uninvited and everyone outside live", () => {
    expect(joinDecision({ team, meeting: live, uid: "stranger" })).toBe("notMember");
    expect(joinDecision({ team: { ...team, deletingAt: 1 }, meeting: live, uid: "o" })).toBe("notMember");
    expect(joinDecision({ team, meeting: undefined, uid: "o" })).toBe("missing");
    expect(joinDecision({ team, meeting: live, uid: "p2" })).toBe("notInvited");
    expect(joinDecision({ team, meeting: adminsOnly, uid: "o" })).toBe("notStarted");
    expect(joinDecision({ team, meeting: { ...live, status: "ended" }, uid: "o" })).toBe("ended");
  });

  it("needs an admitted request when approval is on, except for admins", () => {
    const gated: MeetingDoc = { ...live, requireApproval: true };
    expect(joinDecision({ team, meeting: gated, uid: "p1" })).toBe("needsApproval");
    expect(joinDecision({ team, meeting: gated, uid: "p1", request: { status: "pending" } })).toBe("needsApproval");
    expect(joinDecision({ team, meeting: gated, uid: "p1", request: { status: "denied" } })).toBe("needsApproval");
    expect(joinDecision({ team, meeting: gated, uid: "p1", request: { status: "admitted" } })).toBe("ok");
    expect(joinDecision({ team, meeting: gated, uid: "c" })).toBe("ok");
  });
});

describe("startedRecipients", () => {
  it("is invitees attending, minus the starter and anyone in the lobby", () => {
    const meeting: MeetingDoc = {
      ...everyone,
      startedBy: "c",
      rsvps: { c: "attending", k: "attending", p1: "attending", p2: "notAttending", s: "attending" },
    };
    expect(startedRecipients(team, meeting, ["s"]).sort()).toEqual(["k", "p1"]);
  });

  it("skips attendees no longer invited", () => {
    const meeting: MeetingDoc = { ...adminsOnly, rsvps: { p2: "attending", p1: "attending" } };
    expect(startedRecipients(team, meeting, [])).toEqual(["p1"]);
  });
});

describe("meetingChange", () => {
  it("names what happened", () => {
    expect(meetingChange(undefined, adminsOnly)).toBe("created");
    expect(meetingChange(adminsOnly, { ...adminsOnly, status: "live" })).toBe("started");
    expect(meetingChange(everyone, { ...everyone, status: "ended" })).toBe("ended");
    expect(meetingChange(adminsOnly, undefined)).toBe("cancelled");
    expect(meetingChange({ status: "ended" }, undefined)).toBeNull();
    expect(meetingChange(everyone, { ...everyone, rsvps: { p1: "attending" } })).toBeNull();
  });
});

describe("naming", () => {
  it("prefers the team's name for a member, then their profile", () => {
    expect(displayName(team, "p1", "Patricia")).toBe("Pat");
    expect(displayName(team, "p2", "Sam")).toBe("Sam");
    expect(displayName(team, "p2", undefined)).toBe("Member");
  });

  it("rooms are per meeting", () => {
    expect(roomName("t1", "m1")).toBe("t1_m1");
  });

  it("started notices open the room and use the id the app watches for", () => {
    const n = meetingStartedNotice({ teamId: "t1", meetingId: "m1", teamName: "Rockets", meeting: { title: "Film" } });
    expect(n.route).toBe("/team-meetings/t1/m1/room");
    expect(n.collapseId?.startsWith("meetingStarted_")).toBe(true);
    expect(n.text({}, 1)).toEqual({ title: "Film has started", body: "Rockets · Tap to join" });
  });
});
