// The functions' copy of the @mention parser (src/notifications/mentions.ts)
// against the shared cases (packages/shared/fixtures/mentions), and who a
// team chat message reaches by mention (mentionedReaders).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { type MentionTargets, mentionSpans, mentionsIn } from "../../src/notifications/mentions";
import { mentionedReaders, mentionNotice, type TeamDoc, wants } from "../../src/notifications/model";

const cases = JSON.parse(
  readFileSync(join(__dirname, "../../../../packages/shared/fixtures/mentions/cases.json"), "utf8"),
).cases as Array<Record<string, unknown>>;

describe("the mention parser matches the API and the app", () => {
  const head = cases.find((c) => "members" in c) as unknown as MentionTargets;
  const targets = { members: head.members, roles: head.roles };
  it("finds the same spans and mentions", () => {
    for (const c of cases) {
      if (typeof c.text !== "string") continue;
      expect(mentionSpans(c.text, targets), c.text).toEqual(c.spans);
      expect(mentionsIn(c.text, targets, true), c.text).toEqual(c.mentions);
      expect(mentionsIn(c.text, targets, false), c.text).toEqual(c.mentionsNoGroups);
    }
  });
});

describe("mentionedReaders", () => {
  const team: TeamDoc = {
    members: { o: "owner", c: "captain", p: "player", q: "player", x: "player" },
    memberIds: ["o", "c", "p", "q", "x"],
    memberNames: { o: "Olive", c: "Cam", p: "Pat Lee", q: "Quinn", x: "Xan" },
    roles: { h: { name: "Handlers" } },
    memberRoles: { q: ["h"] },
  };
  const readers = ["o", "c", "p", "q"];

  it("names, roles and @everyone from a captain; never the author or a non-reader", () => {
    expect(mentionedReaders(team, readers, { authorId: "c", text: "@Pat Lee and @Handlers, @Cam @Xan" })).toEqual({
      all: ["p", "q"],
      personal: ["p", "q"],
    });
    expect(mentionedReaders(team, readers, { authorId: "c", text: "@everyone practice moved" })).toEqual({
      all: ["o", "p", "q"],
      personal: [],
    });
  });

  it("a player's @everyone and @role reach no one, but names do", () => {
    expect(mentionedReaders(team, readers, { authorId: "p", text: "@everyone @Handlers @Olive" })).toEqual({
      all: ["o"],
      personal: ["o"],
    });
  });

  it("a member granted manageChats can mention groups", () => {
    const granted = { ...team, memberPerms: { p: ["manageChats"] } };
    expect(mentionedReaders(granted, readers, { authorId: "p", text: "@Handlers" }).personal).toEqual(["q"]);
  });

  it("a personal mention gets through a room mute; @everyone doesn't", () => {
    const prefs = { mutedRooms: ["t/r"] };
    const base = { teamId: "t", roomId: "r", teamName: "T", roomName: "general", message: { authorName: "Cam", text: "@Pat Lee hi" } };
    const personal = mentionNotice({ ...base, personal: true });
    const everyone = mentionNotice({ ...base, personal: false });
    expect(personal.text({}, 1)).toEqual({ title: "#general · T", body: "Cam mentioned you: @Pat Lee hi" });
    expect(personal.extra).toEqual({ mention: true, roomId: "r", personal: true });
    expect(personal.collapseId).toBe("mention_t_r");
    expect(wants(prefs, personal.category, personal.teamId, personal.ignoresRoomMute ? undefined : personal.roomId)).toBe(true);
    expect(wants(prefs, everyone.category, everyone.teamId, everyone.ignoresRoomMute ? undefined : everyone.roomId)).toBe(false);
    // Turning chat off still turns mentions off.
    expect(wants({ categories: { chat: false } }, personal.category, "t", undefined)).toBe(false);
  });
});
