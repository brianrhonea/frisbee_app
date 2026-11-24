// The entry deadline and an entry's checklist (effectiveDeadline,
// entryDeadlineProblem, entryChecklist in tournaments.ts) against the app's
// HostedTournament.effectiveDeadline / deadlineProblem and
// EntryChecklist.of, on fixtures/entry_checklist (written by
// apps/mobile/test/shared_fixtures/entry_checklist_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { effectiveDeadline, entryChecklist, entryDeadlineProblem } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

type Case =
  | { event: Parameters<typeof effectiveDeadline>[0]; deadline: string | null }
  | { check: string | null; startsOn: string; problem: string | null }
  | {
      status: string;
      rosterSize: number | null;
      minRoster: number;
      paid: boolean;
      owes: boolean;
      deadline: string | null;
      now: string;
      checklist: { accepted: boolean; rosterSet: boolean; paid: boolean; owes: boolean; overdue: boolean; complete: boolean };
    };

describe("entry deadline and checklist match the app (fixtures/entry_checklist/cases.json)", () => {
  const cases = fixture<Case>("entry_checklist/cases.json").cases;
  it("works out the same deadline", () => {
    for (const c of cases) if ("event" in c) expect(effectiveDeadline(c.event)?.toISOString() ?? null).toBe(c.deadline);
  });
  it("allows the same deadlines", () => {
    for (const c of cases) {
      if (!("check" in c)) continue;
      expect(entryDeadlineProblem(c.check ? new Date(c.check) : null, new Date(c.startsOn))).toBe(c.problem);
    }
  });
  it("gives the same checklist", () => {
    for (const c of cases) {
      if (!("checklist" in c)) continue;
      const got = entryChecklist({ ...c, deadline: c.deadline ? new Date(c.deadline) : null, now: new Date(c.now) });
      const { deadline: _deadline, ...rest } = got;
      expect(rest).toEqual(c.checklist);
    }
  });
});
