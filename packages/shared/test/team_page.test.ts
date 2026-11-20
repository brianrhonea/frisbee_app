import { describe, expect, it } from "vitest";
import {
  chatSectionMax,
  chatSectionRooms,
  communityOrganizers,
  goingCount,
  groupByLine,
  manageRowLabel,
  nextEventCardText,
  newInChatDescription,
  rosterLineOf,
  setRosterLinesRequestSchema,
  teamMoreSubtitles,
} from "../src/index.js";

describe("roster lines", () => {
  it("reads only known lines", () => {
    expect(rosterLineOf("o")).toBe("o");
    expect(rosterLineOf("both")).toBe("both");
    expect(rosterLineOf("x")).toBeUndefined();
    expect(rosterLineOf(null)).toBeUndefined();
  });

  it("groups O, D, both then unassigned, keeping order, and not at all before anyone has a line", () => {
    const a = { id: "a", line: "d" as const };
    const b: { id: string; line?: "o" | "d" | "both" } = { id: "b" };
    const c = { id: "c", line: "o" as const };
    const d = { id: "d", line: "d" as const };
    expect(groupByLine([a, b, c, d])).toEqual([
      { line: "o", players: [c] },
      { line: "d", players: [a, d] },
      { line: null, players: [b] },
    ]);
    expect(groupByLine<{ id: string; line?: "o" | "d" | "both" }>([b, { id: "e" }])).toEqual([]);
  });

  it("takes lines and nulls by spot id, at least one", () => {
    expect(setRosterLinesRequestSchema.parse({ lines: { a: "o", b: null } })).toEqual({ lines: { a: "o", b: null } });
    expect(() => setRosterLinesRequestSchema.parse({ lines: {} })).toThrow();
    expect(() => setRosterLinesRequestSchema.parse({ lines: { a: "x" } })).toThrow();
    expect(() => setRosterLinesRequestSchema.parse({ lines: { "a/b": "o" } })).toThrow();
  });
});

describe("team page", () => {
  it("counts Going answers only", () => {
    expect(goingCount({ a: "going", b: "maybe", c: "going", d: "notGoing" })).toBe(2);
    expect(goingCount(undefined)).toBe(0);
  });

  it("describes the chat tile by rooms", () => {
    expect(newInChatDescription(0)).toBe("No new messages");
    expect(newInChatDescription(1)).toBe("1 room has new messages");
    expect(newInChatDescription(3)).toBe("3 rooms have new messages");
  });

  it("words More's rows", () => {
    expect(teamMoreSubtitles.playbook).toBe("Plays and whiteboards");
    expect(manageRowLabel("team")).toBe("Manage team");
    expect(manageRowLabel("community")).toBe("Manage group");
  });
});

// The community page (F27); the app's test/domain/team_page_test.dart checks the same cases.
describe("community page", () => {
  it("lists the owner, then anyone who runs the community, by name, with their preset", () => {
    expect(
      communityOrganizers({
        members: { mod: "player", o: "owner", cap: "captain", ev: "player", adm: "player", p: "player", mix: "player" },
        memberNames: { mod: "Mo", o: "Zed", cap: "Cy", ev: "Eve", adm: "Al", p: "Pat", mix: "Max" },
        memberPerms: {
          mod: ["manageChats", "moderate"],
          ev: ["manageChats", "manageEvents", "moderate"],
          adm: ["manageTeam", "manageMembers", "manageChats", "manageEvents", "moderate"],
          mix: ["manageMembers"],
        },
      }),
    ).toEqual([
      { uid: "o", name: "Zed", label: "Owner" },
      { uid: "adm", name: "Al", label: "Admin" },
      { uid: "cap", name: "Cy", label: "Organizer" },
      { uid: "ev", name: "Eve", label: "Organizer" },
      { uid: "mix", name: "Max", label: "Organizer" },
    ]);
    expect(communityOrganizers({})).toEqual([]);
  });

  it("puts unread rooms first, marked, then the rest in order, up to the cap", () => {
    const room = (id: string) => ({ id, name: id });
    const rooms = ["general", "rides", "drills", "socials", "gear", "tourneys", "film"].map(room);
    const s = chatSectionRooms({ rooms, unread: [room("film"), room("rides")] });
    expect(s.rooms.map((r) => [r.room.id, r.unread])).toEqual([
      ["film", true],
      ["rides", true],
      ["general", false],
      ["drills", false],
      ["socials", false],
    ]);
    expect(s.rooms).toHaveLength(chatSectionMax);
    expect(s.more).toBe(2);
    expect(chatSectionRooms({ rooms: [room("general")], unread: [] })).toEqual({ rooms: [{ room: room("general"), unread: false }], more: 0 });
  });

  it("calls a pickup community's next event a pickup, and a school or club's an event", () => {
    expect(nextEventCardText("community")).toEqual({ title: "Next pickup", empty: "No pickup scheduled" });
    expect(nextEventCardText("organization")).toEqual({ title: "Next event", empty: "No events scheduled" });
  });
});
