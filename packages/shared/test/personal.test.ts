import { describe, expect, it } from "vitest";
import {
  ageOn,
  birthDateProblem,
  isCalendarDate,
  personalDetailsProblem,
  personalDetailsSchema,
  phoneProblem,
  tooYoungMessage,
} from "../src/personal.js";

const today = "2026-11-20";

describe("age rules", () => {
  it("counts whole years, birthdays included", () => {
    expect(ageOn("2013-11-20", today)).toBe(13);
    expect(ageOn("2013-11-21", today)).toBe(12);
    expect(ageOn("2008-02-29", "2026-02-28")).toBe(17);
    expect(ageOn("2008-02-29", "2026-03-01")).toBe(18);
  });

  it("refuses under 13, the future and impossible dates", () => {
    expect(birthDateProblem("2014-01-01", today)).toBe(tooYoungMessage);
    expect(birthDateProblem("2013-11-20", today)).toBeNull();
    expect(birthDateProblem("2027-01-01", today)).toBe("That date is in the future.");
    expect(birthDateProblem("1890-01-01", today)).not.toBeNull();
    expect(isCalendarDate("2001-02-29")).toBe(false);
    expect(isCalendarDate("2000-02-29")).toBe(true);
  });

  it("needs a guardian under 18 only", () => {
    expect(personalDetailsProblem({ birthDate: "2010-01-01" }, today)?.field).toBe("guardian");
    expect(personalDetailsProblem({ birthDate: "2000-01-01" }, today)).toBeNull();
  });
});

it("phone numbers", () => {
  expect(phoneProblem("+1 (555) 010-2030")).toBeNull();
  expect(phoneProblem("call me")).not.toBeNull();
  expect(phoneProblem("12345")).not.toBeNull();
});

it("the schema trims, defaults the country and refuses extra fields", () => {
  const base = {
    legalFirstName: " Pat ",
    legalLastName: "Lee",
    birthDate: "1995-04-02",
    phone: "555-010-2030",
    gender: "unspecified",
    address: { line1: "1 Main St", city: "Boston", region: "MA", postalCode: "02110" },
  };
  const ok = personalDetailsSchema.parse(base);
  expect(ok.legalFirstName).toBe("Pat");
  expect(ok.address).toEqual({ ...base.address, line2: "", country: "US" });
  expect(personalDetailsSchema.safeParse({ ...base, ssn: "1" }).success).toBe(false);
  expect(personalDetailsSchema.safeParse({ ...base, address: { ...base.address, country: "USA" } }).success).toBe(false);
});
