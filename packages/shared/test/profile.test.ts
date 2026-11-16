import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  asksForName,
  joinPersonName,
  nameMissing,
  normalizeUsername,
  personNameLimits,
  profileKeywords,
  profileLimits,
  splitDisplayName,
  suggestUsername,
  usernameProblem,
} from "../src/profile.js";

// Written by apps/mobile/test/data/shared_fixtures_test.dart from the app's
// profileKeywords and Username.
const fixture = JSON.parse(readFileSync(new URL("../fixtures/profile_names.json", import.meta.url), "utf8")) as {
  keywords: Array<{ name: string; username: string | null; keywords: string[] }>;
  usernames: Array<{ input: string; normalized: string; problem: string | null }>;
  displayNames: Array<{ name: string | null; first: string; last: string; missing: boolean; suggestion: string }>;
};

describe("profile rules match the app (fixtures/profile_names.json)", () => {
  it.each(fixture.keywords)("keywords for $name / $username", (c) => {
    expect(profileKeywords(c.name, c.username)).toEqual(c.keywords);
  });

  it.each(fixture.usernames)("username $input", (c) => {
    expect(normalizeUsername(c.input)).toBe(c.normalized);
    expect(usernameProblem(c.input)).toBe(c.problem);
  });

  it.each(fixture.displayNames)("display name $name", (c) => {
    expect(splitDisplayName(c.name)).toEqual({ first: c.first, last: c.last });
    expect(nameMissing(c.name)).toBe(c.missing);
    expect(suggestUsername(c.name)).toBe(c.suggestion);
  });
});

describe("Your name and username", () => {
  it("asks Google and Apple accounts, and anyone without a name", () => {
    expect(asksForName("Pat Lee", false)).toBe(true);
    expect(asksForName(null, false)).toBe(true);
    expect(asksForName("", true)).toBe(true);
    expect(asksForName("pat@example.com", true)).toBe(true);
    expect(asksForName("Pat Lee", true)).toBe(false);
  });

  it("joins the boxes into a name that fits the profile", () => {
    expect(joinPersonName(" Pat ", " Lee ")).toBe("Pat Lee");
    expect(joinPersonName("Cher", "")).toBe("Cher");
    expect(personNameLimits.first + 1 + personNameLimits.last).toBeLessThanOrEqual(profileLimits.name);
  });

  it("suggests a username from the joined name", () => {
    expect(suggestUsername(joinPersonName("Mary Ann", "Smith"))).toBe("mary.ann.smith");
    expect(suggestUsername("Al")).toBe("");
  });
});
