// Team chat @mentions (mentions.ts) against the app's
// lib/domain/models/mentions.dart, on fixtures/mentions (written by
// apps/mobile/test/shared_fixtures/mention_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { insertMention, type MentionTargets, mentionQuery, mentionSpans, mentionSuggestions, mentionsIn } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

type Case =
  | { members: MentionTargets["members"]; roles: MentionTargets["roles"] }
  | { text: string; spans: unknown[]; mentions: unknown; mentionsNoGroups: unknown }
  | { query: string; cursor: number; found: unknown }
  | { suggest: string; groups: boolean; results: unknown[] }
  | { insert: string; start: number; cursor: number; label: string; result: unknown };

describe("mentions match the app (fixtures/mentions/cases.json)", () => {
  const cases = fixture<Case>("mentions/cases.json").cases;
  const head = cases.find((c) => "members" in c) as MentionTargets;
  const targets: MentionTargets = { members: head.members, roles: head.roles };

  it("finds the same spans and mentions", () => {
    for (const c of cases) {
      if (!("text" in c)) continue;
      expect(mentionSpans(c.text, targets), c.text).toEqual(c.spans);
      expect(mentionsIn(c.text, targets, true), c.text).toEqual(c.mentions);
      expect(mentionsIn(c.text, targets, false), c.text).toEqual(c.mentionsNoGroups);
    }
  });
  it("finds the same @query at the cursor", () => {
    for (const c of cases) if ("query" in c) expect(mentionQuery(c.query, c.cursor), c.query).toEqual(c.found);
  });
  it("suggests the same targets", () => {
    for (const c of cases) if ("suggest" in c) expect(mentionSuggestions(c.suggest, targets, c.groups), c.suggest).toEqual(c.results);
  });
  it("inserts the same way", () => {
    for (const c of cases) if ("insert" in c) expect(insertMention(c.insert, c.start, c.cursor, c.label)).toEqual(c.result);
  });
});
