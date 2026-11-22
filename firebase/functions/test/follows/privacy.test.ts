import { describe, expect, it } from "vitest";

import { privacyChange, stampFor } from "../../src/follows/privacy";

describe("post privacy (S1)", () => {
  it("changes when a profile turns private or public, not otherwise", () => {
    expect(privacyChange({ name: "A" }, { name: "A", private: true })).toBe(true);
    expect(privacyChange({ private: true }, { private: false })).toBe(false);
    expect(privacyChange(undefined, { private: true })).toBe(true);
    expect(privacyChange(undefined, { name: "A" })).toBeNull();
    expect(privacyChange({ private: true }, { private: true, bio: "x" })).toBeNull();
    expect(privacyChange({ private: false }, { name: "A" })).toBeNull();
    // Deleted: its posts go with the account.
    expect(privacyChange({ private: true }, undefined)).toBeNull();
  });

  it("stamps a new post from its author's profile when it's missing or wrong", () => {
    expect(stampFor({ authorId: "a" }, { private: true })).toBe(true);
    expect(stampFor({ authorId: "a" }, undefined)).toBe(false);
    expect(stampFor({ authorId: "a", private: false }, { private: true })).toBe(true);
    expect(stampFor({ authorId: "a", private: true }, { private: true })).toBeNull();
    expect(stampFor({ authorId: "a", private: false }, { name: "A" })).toBeNull();
    expect(stampFor({ body: "no author" }, { private: true })).toBeNull();
  });
});
