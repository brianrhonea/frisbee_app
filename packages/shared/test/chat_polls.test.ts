// Chat polls (redesign F33): the tally, toggling a choice, and closing.
import { describe, expect, it } from "vitest";
import { chatPollClosed, chatPollTally, chatPollToggle, createChatPollRequestSchema, voteChatPollRequestSchema } from "../src/index.js";

describe("chat polls", () => {
  it("counts each voter once and each option they picked", () => {
    const poll = { options: ["Sat", "Sun", "Both"], votes: { a: [0], b: [0, 2], c: [], d: [2, 2, 9] } };
    expect(chatPollTally(poll)).toEqual({ counts: [2, 0, 2], voters: 3 });
  });

  it("toggles: tap again takes it back; single choice replaces", () => {
    expect(chatPollToggle([], 1, false)).toEqual([1]);
    expect(chatPollToggle([1], 1, false)).toEqual([]);
    expect(chatPollToggle([1], 2, false)).toEqual([2]);
    expect(chatPollToggle([2], 0, true)).toEqual([0, 2]);
    expect(chatPollToggle([0, 2], 2, true)).toEqual([0]);
  });

  it("is closed early or past its closing time", () => {
    const now = Date.UTC(2026, 10, 20);
    expect(chatPollClosed({}, now)).toBe(false);
    expect(chatPollClosed({ closesAt: new Date(now + 1) }, now)).toBe(false);
    expect(chatPollClosed({ closesAt: new Date(now).toISOString() }, now)).toBe(true);
    expect(chatPollClosed({ closedAt: new Date(now - 5) }, now)).toBe(true);
  });

  it("validates a new poll and a vote", () => {
    expect(createChatPollRequestSchema.safeParse({ question: "When?", options: ["Sat"] }).success).toBe(false);
    expect(createChatPollRequestSchema.safeParse({ question: " ", options: ["a", "b"] }).success).toBe(false);
    expect(createChatPollRequestSchema.safeParse({ question: "Q", options: ["a", "b", "c", "d", "e", "f", "g"] }).success).toBe(false);
    expect(createChatPollRequestSchema.parse({ question: " When? ", options: ["Sat ", "Sun"] })).toEqual({
      question: "When?",
      options: ["Sat", "Sun"],
      multiple: false,
    });
    expect(voteChatPollRequestSchema.safeParse({ options: [6] }).success).toBe(false);
    expect(voteChatPollRequestSchema.safeParse({ options: [] }).success).toBe(true);
  });
});
