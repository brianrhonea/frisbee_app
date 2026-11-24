// Registration opens at most 60 days before an event (the app's
// registrationWindowProblem says the same, word for word).
import { describe, expect, it } from "vitest";
import { registrationOpensOn, registrationWindowProblem } from "../src/tournaments.js";

describe("the registration window", () => {
  const now = Date.UTC(2027, 2, 1);
  it("opens 60 days before the start", () => {
    expect(registrationOpensOn(new Date(Date.UTC(2027, 5, 5)))).toEqual(new Date(Date.UTC(2027, 3, 6)));
    expect(registrationWindowProblem(new Date(Date.UTC(2027, 3, 30)), now)).toBeNull();
    expect(registrationWindowProblem(new Date(Date.UTC(2027, 5, 5)), now)).toBe(
      "Registration opens 60 days before the event, on Apr 6, 2027. Keep it as a draft until then.",
    );
    expect(registrationWindowProblem(null, now)).toBe("Set the event's date first.");
  });
});
