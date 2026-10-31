import { describe, expect, it } from "vitest";

import {
  chatNotice,
  directMessageNotice,
  eventChange,
  eventChangeNotice,
  formatWhen,
  messagePreview,
  playNotice,
  reminderNotice,
  reminderRecipients,
  roomReaders,
  same,
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
  });
});

describe("notices", () => {
  it("folds chat repeats into one entry", () => {
    const n = chatNotice({
      teamId: "t1",
      roomId: "general",
      teamName: "Hawks",
      roomName: "General",
      message: { authorName: "Sam", text: "Bring lights" },
    });
    expect(n.collapseId).toBe("chat_t1_general");
    expect(n.route).toBe("/teams/t1/chats/general");
    expect(n.text({}, 1)).toEqual({ title: "General · Hawks", body: "Sam: Bring lights" });
    expect(n.text({}, 3).body).toBe("3 new messages · Sam: Bring lights");
  });

  it("titles direct messages with the sender", () => {
    const n = directMessageNotice({ conversationId: "a_b", message: { authorName: "Sam", text: "yo" } });
    expect(n.text({}, 1)).toEqual({ title: "Sam", body: "yo" });
    expect(n.route).toBe("/messages/a_b");
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
