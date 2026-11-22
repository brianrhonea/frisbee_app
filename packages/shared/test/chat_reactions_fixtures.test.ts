// Chat reactions (chat_reactions.ts) against the app's quickReactions,
// reactionGroups and isChatReaction (apps/mobile/lib/domain/models/chat.dart),
// on the vectors in fixtures/chat_reactions (written by
// apps/mobile/test/shared_fixtures/chat_reactions_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { chatQuickReactions, chatReactionGroups, isChatReaction } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface Case {
  name: string;
  quick?: string[];
  groups?: { name: string; emoji: string[] }[];
  input?: string;
  ok?: boolean;
}

describe("chat reactions match the app (fixtures/chat_reactions/choices.json)", () => {
  it.each(fixture<Case>("chat_reactions/choices.json").cases)("$name", (c) => {
    if (c.quick) {
      expect([...chatQuickReactions]).toEqual(c.quick);
      expect(chatReactionGroups.map((g) => ({ name: g.name, emoji: [...g.emoji] }))).toEqual(c.groups);
    } else {
      expect(isChatReaction(c.input!)).toBe(c.ok);
    }
  });

  it("offers only reactions", () => {
    for (const e of [...chatQuickReactions, ...chatReactionGroups.flatMap((g) => g.emoji)]) expect(isChatReaction(e)).toBe(true);
  });
});
