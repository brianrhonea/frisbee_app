import { describe, expect, it } from "vitest";
import { passwordChecklist, passwordProblem, passwordStrength } from "../src/password.js";

// The same cases as apps/mobile/test/utils/password_policy_test.dart.
describe("passwordProblem", () => {
  it("needs 8+ characters with a letter and a number", () => {
    expect(passwordProblem("abc123")).toBe("At least 8 characters");
    expect(passwordProblem("abcdefgh")).toBe("Use at least one letter and one number");
    expect(passwordProblem("12345678")).toBe("Use at least one letter and one number");
    expect(passwordProblem(" abcd1234")).toBe("Can't start or end with a space");
    expect(passwordProblem("a1".repeat(65))).toBe("At most 128 characters");
    expect(passwordProblem("pull1234")).toBeNull();
    expect(passwordProblem("Huck it deep 7!")).toBeNull();
  });

  it("refuses common passwords whatever their case", () => {
    expect(passwordProblem("Password1")).toBe("Too common. Pick something harder to guess");
    expect(passwordProblem("FRISBEE1")).toBe("Too common. Pick something harder to guess");
  });
});

describe("passwordStrength", () => {
  it("rates by length and variety", () => {
    expect(passwordStrength("abc")).toBe("weak");
    expect(passwordStrength("password1")).toBe("weak");
    expect(passwordStrength("pull1234")).toBe("fair");
    expect(passwordStrength("pullhuck1234")).toBe("good");
    expect(passwordStrength("Huck it deep 7!")).toBe("strong");
    // Repeats count against it.
    expect(passwordStrength("aaaaaaaaaaaa1")).toBe("fair");
  });
});

describe("passwordChecklist", () => {
  it("ticks each requirement met", () => {
    expect(passwordChecklist("abc").map((c) => c.met)).toEqual([false, true, false]);
    expect(passwordChecklist("pull1234").map((c) => c.met)).toEqual([true, true, true]);
  });
});
