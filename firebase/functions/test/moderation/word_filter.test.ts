// The functions' copy of the word filter against the shared cases and lists
// (packages/shared/fixtures/word_filter), and the backstop's fixes.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { textFix } from "../../src/moderation/text_filter";
import {
  blockedEndings,
  blockedPhrases,
  blockedTerms,
  filterText,
  maskedEndings,
  maskedTerms,
} from "../../src/moderation/word_filter";

const dir = join(__dirname, "../../../../packages/shared/fixtures/word_filter");
const read = (f: string) => JSON.parse(readFileSync(join(dir, f), "utf8"));

describe("the word filter matches the API and the app", () => {
  it("has the same lists", () => {
    expect(read("lists.json")).toEqual({ blockedTerms, blockedPhrases, maskedTerms, blockedEndings, maskedEndings });
  });
  it.each(read("cases.json").cases as Array<{ name: string; input: string; text: string; blocked: boolean }>)(
    "$name",
    (c) => expect(filterText(c.input)).toEqual({ text: c.text, blocked: c.blocked }),
  );
});

describe("textFix", () => {
  it("leaves clean text alone", () => {
    expect(textFix({ body: "Nice hucks" }, ["body"], "delete")).toBeNull();
  });
  it("masks mild swearing", () => {
    expect(textFix({ title: "Damn", body: "holy shit" }, ["title", "body"], "delete")).toEqual({ body: "holy s***" });
  });
  it("deletes a message with a blocked word", () => {
    expect(textFix({ text: "kys" }, ["text"], "delete")).toBe("delete");
  });
  it("replaces a blocked name", () => {
    expect(textFix({ name: "the f@gs", notes: "shit" }, ["name", "notes"], "replace")).toEqual({
      name: "Removed",
      notes: "s***",
    });
  });
  it("leaves masked text alone, so the rewrite doesn't loop", () => {
    expect(textFix({ body: "holy s***" }, ["body"], "delete")).toBeNull();
  });
});
