import { describe, expect, it } from "vitest";
import { adultOnlyMessage } from "../src/account_gate.js";
import {
  ageOn,
  birthDateProblem,
  canJoinClubTeam,
  clubCantJoinMessage,
  clubJoinProblem,
  clubMinimumAge,
  clubNeedsBirthDateMessage,
  clubTooYoungMessage,
  isCalendarDate,
  personalDetailsProblem,
  personalDetailsSchema,
  phoneProblem,
  tooYoungMessage,
} from "../src/personal.js";
import { isClubTeam } from "../src/team.js";

const today = "2026-11-20";

describe("age rules", () => {
  it("counts whole years, birthdays included", () => {
    expect(ageOn("2013-11-20", today)).toBe(13);
    expect(ageOn("2013-11-21", today)).toBe(12);
    expect(ageOn("2008-02-29", "2026-02-28")).toBe(17);
    expect(ageOn("2008-02-29", "2026-03-01")).toBe(18);
  });

  it("refuses under 18 (under 13 with its own message), the future and impossible dates", () => {
    expect(birthDateProblem("2014-01-01", today)).toBe(tooYoungMessage);
    expect(birthDateProblem("2013-11-20", today)).toBe(adultOnlyMessage);
    expect(birthDateProblem("2008-11-21", today)).toBe(adultOnlyMessage);
    expect(birthDateProblem("2008-11-20", today)).toBeNull();
    expect(birthDateProblem("2027-01-01", today)).toBe("That date is in the future.");
    expect(birthDateProblem("1890-01-01", today)).not.toBeNull();
    expect(isCalendarDate("2001-02-29")).toBe(false);
    expect(isCalendarDate("2000-02-29")).toBe(true);
  });

  it("is adults only: under 18 is a birthDate problem, never a guardian step", () => {
    expect(personalDetailsProblem({ birthDate: "2010-01-01" }, today)).toEqual({ field: "birthDate", message: adultOnlyMessage });
    expect(personalDetailsProblem({ birthDate: "2020-01-01" }, today)).toEqual({ field: "birthDate", message: tooYoungMessage });
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

describe("club teams (16 and over)", () => {
  it("lets people join from their 16th birthday", () => {
    expect(canJoinClubTeam("2010-11-20", today)).toBe(true);
    expect(clubJoinProblem("2010-11-20", today)).toBeNull();
    expect(canJoinClubTeam("1990-05-01", today)).toBe(true);
  });

  it("refuses the day before, and anyone younger", () => {
    expect(canJoinClubTeam("2010-11-21", today)).toBe(false);
    expect(clubJoinProblem("2010-11-21", today)).toBe(clubTooYoungMessage);
    expect(clubJoinProblem("2012-01-01", new Date("2026-11-20T12:00:00Z"))).toBe(clubTooYoungMessage);
    expect(clubTooYoungMessage).toBe("Club teams are for players 16 and over.");
    expect(clubMinimumAge).toBe(16);
  });

  it("counts a 29 February birthday on the day in leap years", () => {
    expect(canJoinClubTeam("2008-02-29", "2024-02-28")).toBe(false);
    expect(canJoinClubTeam("2008-02-29", "2024-02-29")).toBe(true);
    expect(canJoinClubTeam("2008-02-29", "2024-03-01")).toBe(true);
  });

  it("needs a date of birth on file", () => {
    expect(canJoinClubTeam(null, today)).toBe(false);
    expect(clubJoinProblem(undefined, today)).toBe(clubNeedsBirthDateMessage);
    expect(clubJoinProblem("not a date", today)).toBe(clubNeedsBirthDateMessage);
    expect(clubNeedsBirthDateMessage).toBe("Add your date of birth in About you to join a club team.");
  });

  it("names who can't join for an admin", () => {
    expect(clubCantJoinMessage("Sam")).toBe("Sam can't join a club team: club teams are for players 16 and over.");
  });

  it("only club-level teams are club teams", () => {
    expect(isClubTeam({ level: "club" })).toBe(true);
    expect(isClubTeam({ kind: "team", level: "club" })).toBe(true);
    expect(isClubTeam({})).toBe(true);
    for (const level of ["college", "youth", "league", "pickup"]) expect(isClubTeam({ level })).toBe(false);
    expect(isClubTeam({ kind: "community", level: "club" })).toBe(false);
    expect(isClubTeam({ kind: "organization", level: "club" })).toBe(false);
  });
});
