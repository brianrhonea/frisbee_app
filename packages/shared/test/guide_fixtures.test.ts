// Stall 10's guides (guides.ts) against the app's
// lib/domain/models/guides.dart, on fixtures/guides (written by
// apps/mobile/test/shared_fixtures/guide_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { helpTopics, officialRules, rulesGuide } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

describe("guides match the app (fixtures/guides/guides.json)", () => {
  const cases = fixture<Record<string, unknown>>("guides/guides.json").cases;
  const pick = (k: string) => cases.find((c) => k in c)?.[k];
  it("links the same official rules", () => expect(officialRules).toEqual(pick("officialRules")));
  it("has the same rules guide", () => expect(rulesGuide).toEqual(pick("rules")));
  it("has the same help topics", () => expect(helpTopics).toEqual(pick("help")));
});
