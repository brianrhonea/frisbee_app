import { describe, expect, it } from "vitest";

import {
  chatNotice,
  directMessageNotice,
  directMessageRecipients,
  messageRequestNotice,
  eventChange,
  eventViewers,
  eventChangeNotice,
  formatWhen,
  messagePreview,
  joinRequestNotice,
  teamInviteNotice,
  calendarInviteNotice,
  playNotice,
  reminderNotice,
  reminderRecipients,
  roomReaders,
  quietRepeatMs,
  same,
  shouldPush,
  wants,
} from "../../src/notifications/model";

/** Stands in for a Firestore Timestamp. */
const ts = (iso: string) => ({ toMillis: () => Date.parse(iso) });

// Sun, Nov 1 2026, 6:00 PM in Denver (UTC-6 by then).
const start = "2026-11-02T00:00:00Z";
const denver = { utcOffsetMinutes: -360 };

describe("wants", () => {
  it("is on until turned off", () => {
    expect(wants(undefined, "chat", "t1", "general")).toBe(true);
    expect(wants({ categories: { chat: false } }, "chat", "t1")).toBe(false);
  });

  it("lets a team override the default either way", () => {
    const prefs = {
      categories: { chat: false, eventChanges: true },
      teams: { t1: { chat: true, eventChanges: false } },
    };
    expect(wants(prefs, "chat", "t1")).toBe(true);
    expect(wants(prefs, "chat", "t2")).toBe(false);
    expect(wants(prefs, "eventChanges", "t1")).toBe(false);
  });

  it("silences muted rooms only", () => {
    const prefs = { mutedRooms: ["t1/general"] };
    expect(wants(prefs, "chat", "t1", "general")).toBe(false);
    expect(wants(prefs, "chat", "t1", "caps")).toBe(true);
  });

  it("silences muted conversations only", () => {
    const prefs = { mutedRooms: ["dm/a_b"] };
    expect(wants(prefs, "directMessages", undefined, undefined, "a_b")).toBe(false);
    expect(wants(prefs, "directMessages", undefined, undefined, "a_c")).toBe(true);
  });
});

describe("roomReaders", () => {
  const team = {
    members: { o: "owner", c: "coach", p: "player", s: "stats", guest: "player" },
  };

  it("includes the owner, the room's roles and its people", () => {
    const room = { readRoles: ["coach"], readUsers: ["guest"] };
    expect(roomReaders(team, room).sort()).toEqual(["c", "guest", "o"]);
  });

  it("treats a legacy stats member as a player", () => {
    expect(roomReaders(team, { readRoles: ["player"] }).sort()).toEqual(["guest", "o", "p", "s"]);
  });
});

describe("eventChange", () => {
  const base = { title: "Practice", startsAt: ts(start), location: "Field 2", poll: null };

  it("reports adds and deletes", () => {
    expect(eventChange(undefined, base)).toBe("created");
    expect(eventChange(base, undefined)).toBe("deleted");
  });

  it("ignores RSVPs, reactions and votes", () => {
    expect(eventChange(base, { ...base, rsvps: { u1: "going" }, votes: { u1: ["a"] } })).toBeNull();
  });

  it("compares timestamps by value", () => {
    expect(eventChange(base, { ...base, startsAt: ts(start) })).toBeNull();
    expect(eventChange(base, { ...base, startsAt: ts("2026-11-02T01:00:00Z") })).toBe("updated");
  });

  it("treats a missing field as null", () => {
    expect(eventChange(base, { title: "Practice", startsAt: ts(start), location: "Field 2" })).toBeNull();
  });
});

describe("same", () => {
  it("ignores key order in maps", () => {
    expect(same({ a: 1, b: [1, { c: 2 }] }, { b: [1, { c: 2 }], a: 1 })).toBe(true);
    expect(same({ a: 1 }, { a: 2 })).toBe(false);
  });
});

describe("formatWhen", () => {
  it("uses the recipient's offset", () => {
    expect(formatWhen(Date.parse(start), -360)).toBe("Sun, Nov 1 at 6:00 PM");
  });

  it("says UTC when there's no offset", () => {
    expect(formatWhen(Date.parse("2026-11-02T09:05:00Z"))).toBe("Mon, Nov 2 at 9:05 AM UTC");
  });
});

describe("messagePreview", () => {
  it("collapses whitespace and summarises attachments", () => {
    expect(messagePreview({ text: "  hi\n  there " })).toBe("hi there");
    expect(messagePreview({ text: "", attachments: [{ contentType: "image/png" }] })).toBe("📷 Photo");
    expect(messagePreview({ attachments: [{ contentType: "application/pdf" }, {}] })).toBe("📎 2 files");
    expect(messagePreview({ attachments: [{ contentType: "video/mp4" }] })).toBe("🎬 Video");
  });
});

describe("notices", () => {
  it("folds chat into one feed entry but pushes each message's own text", () => {
    const n = chatNotice({
      teamId: "t1",
      roomId: "general",
      teamName: "Hawks",
      roomName: "General",
      message: { authorName: "Sam", text: "Bring lights" },
      messageId: "m1",
    });
    expect(n.collapseId).toBe("chat_t1_general");
    expect(n.pushId).toBe("m1");
    expect(n.route).toBe("/teams/t1/chats/general");
    expect(n.text({}, 1)).toEqual({ title: "General · Hawks", body: "Sam: Bring lights" });
    expect(n.text({}, 3).body).toBe("Sam: Bring lights");
  });

  it("titles direct messages with the sender", () => {
    const n = directMessageNotice({ conversationId: "a_b", message: { authorName: "Sam", text: "yo" }, messageId: "m9" });
    expect(n.text({}, 1)).toEqual({ title: "Sam", body: "yo" });
    expect(n.text({}, 4)).toEqual({ title: "Sam", body: "yo" });
    expect(n.route).toBe("/messages/a_b");
    expect(n.conversationId).toBe("a_b");
    expect(n.pushId).toBe("m9");
    const g = directMessageNotice({
      conversationId: "g-1",
      message: { authorName: "Sam", text: "yo" },
      conversation: { kind: "group", name: "Carpool" },
    });
    expect(g.text({}, 1)).toEqual({ title: "Carpool", body: "Sam: yo" });
    expect(g.collapseId).toBe("dm_g-1");
  });

  it("tells a request's recipient quietly, and a decliner nothing", () => {
    const conv = (extra: Record<string, unknown> = {}) => ({ participants: ["a", "b"], ...extra });
    expect(directMessageRecipients(conv(), "a")).toEqual({ direct: ["b"], requests: [] });
    expect(directMessageRecipients(conv({ status: "request", requestedOf: "b" }), "a")).toEqual({
      direct: [],
      requests: ["b"],
    });
    expect(directMessageRecipients(conv({ status: "declined", requestedOf: "b" }), "a")).toEqual({
      direct: [],
      requests: [],
    });
    // The sender of a request still hears the replies once it's accepted.
    expect(directMessageRecipients(conv({ status: "accepted", requestedOf: "b" }), "b")).toEqual({
      direct: ["a"],
      requests: [],
    });
    expect(directMessageRecipients(undefined, "a")).toEqual({ direct: [], requests: [] });
    const n = messageRequestNotice({ message: { authorName: "Sam", text: "secret" } });
    expect(n.collapseId).toBe("dmRequests");
    expect(n.text({}, 1)).toEqual({ title: "New message request", body: "Sam wants to send you a message." });
    expect(JSON.stringify(n.text({}, 1))).not.toContain("secret");
    expect(n.text({}, 2).title).toBe("2 new message requests");
  });

  it("words event changes in the recipient's time", () => {
    const event = { title: "Hat league", type: "game", startsAt: ts(start), location: "Riverside" };
    const created = eventChangeNotice({ change: "created", teamId: "t1", eventId: "e1", teamName: "Hawks", after: event });
    expect(created.text(denver, 1)).toEqual({
      title: "Hawks: new game",
      body: "Hat league · Sun, Nov 1 at 6:00 PM · Riverside",
    });
    expect(created.route).toBe("/team-events/t1/e1");

    const moved = eventChangeNotice({
      change: "updated",
      teamId: "t1",
      eventId: "e1",
      teamName: "Hawks",
      before: { ...event, startsAt: ts("2026-11-01T23:00:00Z") },
      after: event,
    });
    expect(moved.text(denver, 1).body).toBe("New time · Sun, Nov 1 at 6:00 PM · Riverside");

    const cancelled = eventChangeNotice({ change: "deleted", teamId: "t1", eventId: "e1", teamName: "Hawks", before: event });
    expect(cancelled.text(denver, 1).title).toBe("Hawks: Hat league cancelled");
    expect(cancelled.route).toBe("/teams/t1/events");
  });

  it("reminds everyone who hasn't said they can't go", () => {
    const event = { title: "", type: "practice", startsAt: ts(start), rsvps: { a: "going", b: "notGoing", c: "maybe" } };
    expect(reminderRecipients({ memberIds: ["a", "b", "c", "d"] }, event)).toEqual(["a", "c", "d"]);
    const n = reminderNotice({ event, route: "/team-events/t1/e1", teamId: "t1", teamName: "Hawks" });
    expect(n.text(denver, 1)).toEqual({ title: "Tomorrow: Practice", body: "Hawks · Sun, Nov 1 at 6:00 PM" });
  });

  it("announces new and saved plays", () => {
    const n = playNotice({ created: true, teamId: "t1", playId: "p1", teamName: "Hawks", play: { name: "Ho stack" } });
    expect(n.text({}, 1)).toEqual({ title: "Hawks: new play", body: "Ho stack" });
    expect(n.route).toBe("/teams/t1/plays/p1");
  });
});

describe("joinRequestNotice", () => {
  it("names who wants in, and folds repeats", () => {
    const n = joinRequestNotice({ teamId: "g1", teamName: "Sunday Pickup", request: { name: "Sam" } });
    expect(n.text({}, 1)).toEqual({ title: "Sunday Pickup: request to join", body: "Sam wants to join" });
    expect(n.text({}, 3).body).toBe("3 people want to join · Sam");
    expect(n.route).toBe("/teams/g1/members");
    expect(n.category).toBe("teamActivity");
  });
});

describe("teamInviteNotice", () => {
  it("says who invited them, and to what", () => {
    const n = teamInviteNotice({
      teamId: "g1",
      invite: { teamName: "Sunday Pickup", invitedByName: "Ana", kind: "community" },
    });
    expect(n.text({}, 1)).toEqual({
      title: "You're invited to join Sunday Pickup",
      body: "Ana invited you to their group. Tap to accept or decline.",
    });
    expect(n.route).toBe("/teams");
  });
});

describe("calendarInviteNotice", () => {
  it("says who shared which calendar, and what they may do", () => {
    const n = calendarInviteNotice({ calendarId: "c1", invite: { calendarName: "Training", role: "edit" }, fromName: "Ana" });
    expect(n.text({}, 1)).toEqual({
      title: "Ana shared a calendar with you",
      body: 'Accept to see and add events on "Training".',
    });
    expect(n.route).toBe("/settings/calendar");
    expect(n.category).toBe("social");
    const view = calendarInviteNotice({ calendarId: "c1", invite: { role: "view" }, fromName: "" });
    expect(view.text({}, 1)).toEqual({ title: "Someone shared a calendar with you", body: 'Accept to see its events on "a calendar".' });
  });
});

describe("shouldPush", () => {
  const now = 1_000_000_000;
  const at = (ms: number) => ({ toMillis: () => ms });

  it("pushes something new, or a repeat of one already read", () => {
    expect(shouldPush(undefined, now)).toBe(true);
    expect(shouldPush({ read: true, pushedAt: at(now - 1000) }, now)).toBe(true);
  });

  it("keeps quick repeats of an unread one quiet, then pushes again", () => {
    expect(shouldPush({ read: false, pushedAt: at(now - 60_000) }, now)).toBe(false);
    expect(shouldPush({ read: false, pushedAt: at(now - quietRepeatMs) }, now)).toBe(true);
  });

  it("pushes unread entries from before push times were kept", () => {
    expect(shouldPush({ read: false }, now)).toBe(true);
    expect(shouldPush({ read: false, pushedAt: null }, now)).toBe(true);
  });

  it("pushes every message, however quick", () => {
    expect(shouldPush({ read: false, pushedAt: at(now - 1000) }, now, true)).toBe(true);
  });
});

describe("who sees a community event", () => {
  const team = {
    kind: "organization",
    members: { o: "owner", a: "player", b: "player", m: "player" },
    memberIds: ["o", "a", "b", "m"],
    memberRoles: { a: ["woof"], b: ["whip"] },
    memberPerms: { m: ["manageEvents"] },
  };

  it("is its audience, the owner and event managers", () => {
    expect(eventViewers(team, { audience: ["woof"] })).toEqual(["o", "a", "m"]);
    expect(eventViewers(team, { audience: ["everyone"] })).toEqual(["o", "a", "b", "m"]);
    expect(eventViewers({ ...team, kind: undefined }, { audience: ["woof"] })).toEqual(["o", "a", "b", "m"]);
  });

  it("lets custom roles read chat rooms", () => {
    expect(roomReaders(team, { readRoles: ["whip"] })).toEqual(["o", "b"]);
  });
});
