import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { normalizeUsername, profileKeywords, usernameProblem } from "../src/profile.js";

// Written by apps/mobile/test/data/shared_fixtures_test.dart from the app's
// profileKeywords and Username.
const fixture = JSON.parse(readFileSync(new URL("../fixtures/profile_names.json", import.meta.url), "utf8")) as {
  keywords: Array<{ name: string; username: string | null; keywords: string[] }>;
  usernames: Array<{ input: string; normalized: string; problem: string | null }>;
};

describe("profile rules match the app (fixtures/profile_names.json)", () => {
  it.each(fixture.keywords)("keywords for $name / $username", (c) => {
    expect(profileKeywords(c.name, c.username)).toEqual(c.keywords);
  });

  it.each(fixture.usernames)("username $input", (c) => {
    expect(normalizeUsername(c.input)).toBe(c.normalized);
    expect(usernameProblem(c.input)).toBe(c.problem);
  });
});
