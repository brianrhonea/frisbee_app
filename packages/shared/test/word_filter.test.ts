// The word filter (word_filter.ts) on the hand-written cases in
// fixtures/word_filter/cases.json, which the app's word_filter.dart is
// tested against too; and its lists against fixtures/word_filter/lists.json,
// which the app's test also checks, so both platforms filter alike.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  blockedEndings,
  blockedPhrases,
  blockedTerms,
  filterText,
  maskedEndings,
  maskedTerms,
  normalizeWord,
} from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface Case {
  name: string;
  input: string;
  text: string;
  blocked: boolean;
}

describe("filterText (fixtures/word_filter/cases.json)", () => {
  it.each(fixture<Case>("word_filter/cases.json").cases)("$name", (c) => {
    expect(filterText(c.input)).toEqual({ text: c.text, blocked: c.blocked });
  });
});

describe("the lists", () => {
  it("match fixtures/word_filter/lists.json (the app checks the same file)", () => {
    const lists = JSON.parse(readFileSync(new URL("../fixtures/word_filter/lists.json", import.meta.url), "utf8"));
    expect(lists).toEqual({ blockedTerms, blockedPhrases, maskedTerms, blockedEndings, maskedEndings });
  });

  it("are lower-case, normalized, sorted and don't overlap", () => {
    for (const list of [blockedTerms, maskedTerms]) {
      for (const t of list) expect(normalizeWord(t)).toBe(t);
      expect([...list]).toEqual([...list].sort());
    }
    expect(blockedTerms.filter((t) => maskedTerms.includes(t))).toEqual([]);
  });
});
