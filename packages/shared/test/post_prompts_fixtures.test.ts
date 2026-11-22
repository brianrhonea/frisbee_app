// The composer's rotating hints (post_prompts.ts) against the app's
// (apps/mobile/lib/domain/models/post_prompts.dart), on fixtures/post_prompts.
import { describe, expect, it } from "vitest";
import { postPrompt, postPrompts } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

describe("the composer's prompts match the app (fixtures/post_prompts/prompts.json)", () => {
  it.each(fixture<{ turn: number; prompt: string; all: string[] }>("post_prompts/prompts.json").cases)("turn $turn", (c) => {
    expect(postPrompt(c.turn)).toBe(c.prompt);
    expect([...postPrompts]).toEqual(c.all);
  });
});
