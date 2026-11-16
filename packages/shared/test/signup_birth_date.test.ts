// PUT /v1/me/personal/birth-date's body (packages/shared/src/personal.ts).
import { describe, expect, it } from "vitest";
import { signUpBirthDateSchema } from "../src/personal.js";

describe("signUpBirthDateSchema", () => {
  it("takes only a real calendar date", () => {
    expect(signUpBirthDateSchema.safeParse({ birthDate: "2000-02-29" }).success).toBe(true);
    expect(signUpBirthDateSchema.safeParse({ birthDate: "2001-02-29" }).success).toBe(false);
    expect(signUpBirthDateSchema.safeParse({}).success).toBe(false);
    expect(signUpBirthDateSchema.safeParse({ birthDate: "2000-01-01", phone: "1" }).success).toBe(false);
  });
});
