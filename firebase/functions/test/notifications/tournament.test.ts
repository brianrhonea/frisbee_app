import { describe, expect, it } from "vitest";

import type { Prefs } from "../../src/notifications/model";
import {
  becameFinal,
  deadlineOf,
  entryDeadlineNotice,
  finalNotice,
  missingFor,
  reminderDue,
  reminderLeadMs,
  scheduleCameOut,
  tournamentInviteNotice,
} from "../../src/notifications/tournament";

const prefs = {} as Prefs;
const day = 24 * 60 * 60 * 1000;
const starts = Date.UTC(2026, 11, 5);
const fee = (o: Record<string, unknown> = {}) => ({ amountCents: 25000, currency: "USD", instructions: "", dueAt: null, ...o });

describe("the entry deadline (effectiveDeadline)", () => {
  it("the event's deadline, else the fee's due date, else the day before it starts", () => {
    expect(deadlineOf({ startsOn: new Date(starts), entryDeadline: new Date(starts - 5 * day), bidFee: fee({ dueAt: new Date(starts - 9 * day) }) })).toBe(starts - 5 * day);
    expect(deadlineOf({ startsOn: new Date(starts), bidFee: fee({ dueAt: new Date(starts - 9 * day) }) })).toBe(starts - 9 * day);
    expect(deadlineOf({ startsOn: new Date(starts) })).toBe(starts - day);
    expect(deadlineOf({})).toBeNull();
  });
});

describe("what's missing", () => {
  const t = { entryType: "teams", bidFee: fee() };
  it("a roster under the minimum, and an unpaid fee", () => {
    expect(missingFor({ t, entry: { roster: ["a", "b"] }, minRoster: 7, payment: undefined, player: false })).toEqual(["roster", "payment"]);
    expect(missingFor({ t, entry: { roster: Array.from({ length: 7 }, (_, i) => `p${i}`) }, minRoster: 7, payment: { paid: true }, player: false })).toEqual([]);
  });
  it("the host's own team has no fee", () => {
    const hosted = { ...t, hostId: "host" };
    expect(missingFor({ t: hosted, entry: { roster: [] }, minRoster: 2, payment: undefined, player: false, teamId: "host" })).toEqual(["roster"]);
    expect(missingFor({ t: hosted, entry: { roster: [] }, minRoster: 2, payment: undefined, player: false, teamId: "other" })).toEqual(["roster", "payment"]);
  });
  it("teams reserving spots fill their roster later; free events owe nothing", () => {
    const mixed = { entryType: "players", teamEntry: true, bidFee: fee(), teamFee: fee() };
    expect(missingFor({ t: mixed, entry: {}, minRoster: 7, payment: undefined, player: false })).toEqual(["payment"]);
    expect(missingFor({ t: { entryType: "teams", bidFee: null }, entry: { roster: [] }, minRoster: 2, payment: undefined, player: false })).toEqual(["roster"]);
  });
  it("a player owes the bid fee of a player event, and has no roster", () => {
    const hat = { entryType: "players", bidFee: fee() };
    expect(missingFor({ t: hat, entry: {}, minRoster: 0, payment: undefined, player: true })).toEqual(["payment"]);
    expect(missingFor({ t: hat, entry: {}, minRoster: 0, payment: { paid: true }, player: true })).toEqual([]);
  });
});

describe("when a reminder is due", () => {
  const deadline = starts - day;
  it("'soon' within three days, 'passed' for a day after, never without a deadline", () => {
    expect(reminderDue(deadline, deadline - reminderLeadMs - 1, undefined)).toBeNull();
    expect(reminderDue(deadline, deadline - reminderLeadMs + 1, undefined)).toBe("soon");
    expect(reminderDue(deadline, deadline + 1, undefined)).toBe("passed");
    expect(reminderDue(deadline, deadline + 2 * day, undefined)).toBeNull();
    expect(reminderDue(null, deadline, undefined)).toBeNull();
  });
  it("each once", () => {
    expect(reminderDue(deadline, deadline - day, { soon: true })).toBeNull();
    expect(reminderDue(deadline, deadline + 1, { passed: true })).toBeNull();
  });
});

describe("notices", () => {
  it("an invite opens the respond flow for that team, with its reply-by day", () => {
    const n = tournamentInviteNotice({ tournamentId: "t1", teamId: "red", eventName: "Spring Fling", teamName: "Red", replyBy: Date.UTC(2026, 10, 21, 12) });
    expect(n.route).toBe("/tournaments/t1/respond?team=red");
    expect(n.text(prefs, 1)).toEqual({ title: "Red is invited", body: "Spring Fling invited your team. Respond by Sat, Nov 21." });
  });
  it("deadline reminders say what's left", () => {
    const soon = entryDeadlineNotice({ tournamentId: "t1", teamId: "red", eventName: "Spring Fling", kind: "soon", missing: ["roster", "payment"], deadline: Date.UTC(2026, 11, 4) });
    expect(soon.text(prefs, 1).body).toBe("Spring Fling: set your roster and pay the entry fee before the deadline.");
    const passed = entryDeadlineNotice({ tournamentId: "t1", teamId: null, eventName: "Hat", kind: "passed", missing: ["payment"], deadline: Date.UTC(2026, 11, 4) });
    expect(passed.route).toBe("/tournaments/t1");
    expect(passed.text(prefs, 1).title).toBe("Entry deadline passed");
  });
  it("the schedule comes out once, when it first becomes scheduled", () => {
    expect(scheduleCameOut({ status: "seeding" }, { status: "scheduled" })).toBe(true);
    expect(scheduleCameOut({ status: "registration" }, { status: "scheduled" })).toBe(true);
    expect(scheduleCameOut({ status: "scheduled" }, { status: "scheduled" })).toBe(false);
    expect(scheduleCameOut({ status: "live" }, { status: "scheduled" })).toBe(false);
  });
  it("a final, not a running score or a report", () => {
    expect(becameFinal({ status: "reported" }, { status: "done", scoreA: 15, scoreB: 12 })).toBe(true);
    expect(becameFinal({ status: "done", scoreA: 15, scoreB: 12 }, { status: "done", scoreA: 15, scoreB: 13 })).toBe(false);
    expect(becameFinal({ status: "scheduled" }, { status: "scheduled", live: { scoreA: 3, scoreB: 2 } })).toBe(false);
    const n = finalNotice({ tournamentId: "t1", gameId: "g001", eventName: "Spring Fling", nameA: "Red", nameB: "Blue", scoreA: 15, scoreB: 12 });
    expect(n.text(prefs, 1).title).toBe("Final: Red 15–12 Blue");
  });
});
