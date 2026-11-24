// Notices for hosted tournaments and leagues: a team invited, entry
// deadlines (roster and fee), the schedule out, and a final score. Pure,
// like model.ts, so it's unit-tested in test/notifications/tournament.test.ts.
// The triggers that send them are in triggers.ts (tournamentInvite,
// tournamentScheduled, tournamentFinal, entryDeadlineReminders).

import type { Data, Notice } from "./model";

const dayMs = 24 * 60 * 60 * 1000;

/** How long before the deadline the first reminder goes. */
export const reminderLeadMs = 3 * dayMs;

const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);

/** A stored time (a Timestamp, a Date or an ISO string) as millis, or null. */
export function millisOf(v: unknown): number | null {
  if (v == null) return null;
  if (v instanceof Date) return v.getTime();
  if (typeof v === "string") {
    const t = Date.parse(v);
    return Number.isNaN(t) ? null : t;
  }
  const ts = v as { toMillis?: () => number };
  return typeof ts.toMillis === "function" ? ts.toMillis() : null;
}

/** The fee a team pays to enter (spotFee in packages/shared), or null. */
export function teamFeeOf(t: Data): Data | null {
  const fee = t.entryType === "players" ? (t.teamEntry === true ? t.teamFee : null) : t.bidFee;
  return fee && typeof fee === "object" ? (fee as Data) : null;
}

/** What a player pays to sign up (the bid fee of a player-entry event), or null. */
export function playerFeeOf(t: Data): Data | null {
  return t.entryType === "players" && t.bidFee && typeof t.bidFee === "object" ? (t.bidFee as Data) : null;
}

const owes = (fee: Data | null) => !!fee && typeof fee.amountCents === "number" && fee.amountCents > 0;

/**
 * When rosters and fees are due (effectiveDeadline in packages/shared):
 * the entry deadline, else the fee's due date, else the day before it starts.
 */
export function deadlineOf(t: Data): number | null {
  const set = millisOf(t.entryDeadline);
  if (set != null) return set;
  const fee = t.entryType === "players" ? (teamFeeOf(t) ?? playerFeeOf(t)) : teamFeeOf(t);
  const due = millisOf(fee?.dueAt);
  if (due != null) return due;
  const starts = millisOf(t.startsOn);
  return starts == null ? null : starts - dayMs;
}

/** What's still missing from an entry: its roster (under the minimum) and its fee (unpaid). */
export function missingFor(a: {
  t: Data;
  entry: Data | null;
  /** The division's roster minimum (effectiveMinRoster). */
  minRoster: number;
  /** payments/{payerId}, if any. */
  payment: Data | undefined;
  /** A player's signup rather than a team's entry. */
  player: boolean;
}): Array<"roster" | "payment"> {
  const out: Array<"roster" | "payment"> = [];
  const mixed = a.t.entryType === "players" && a.t.teamEntry === true;
  if (!a.player && !mixed && strings(a.entry?.roster).length < a.minRoster) out.push("roster");
  if (owes(a.player ? playerFeeOf(a.t) : teamFeeOf(a.t)) && a.payment?.paid !== true) out.push("payment");
  return out;
}

export type ReminderKind = "soon" | "passed";

/**
 * The reminder due now for something still missing, or null: "soon" from
 * reminderLeadMs before the deadline until it passes, "passed" once it's
 * gone (up to a day after); each once ([sent] holds what went before).
 */
export function reminderDue(deadline: number | null, now: number, sent: Data | undefined): ReminderKind | null {
  if (deadline == null) return null;
  if (now > deadline) return now - deadline <= dayMs && !sent?.passed ? "passed" : null;
  return deadline - now <= reminderLeadMs && !sent?.soon && !sent?.passed ? "soon" : null;
}

const whatsLeft = (missing: Array<"roster" | "payment">) =>
  missing.length === 2 ? "set your roster and pay the entry fee" : missing[0] === "roster" ? "set your roster" : "pay the entry fee";

/** "Fri, Dec 4" in the recipient's time zone. */
function dayLabel(at: number, offsetMinutes: number | undefined): string {
  const d = new Date(at + (offsetMinutes ?? 0) * 60_000);
  return d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" });
}

/** A host invited a team: its admins, to respond. */
export function tournamentInviteNotice(a: { tournamentId: string; teamId: string; eventName: string; teamName: string; replyBy: number | null }): Notice {
  const event = a.eventName || "a tournament";
  return {
    category: "teamActivity",
    teamId: a.teamId,
    route: `/tournaments/${a.tournamentId}/respond?team=${a.teamId}`,
    collapseId: `invite_${a.tournamentId}_${a.teamId}`,
    text: (prefs) => ({
      title: `${a.teamName || "Your team"} is invited`,
      body: a.replyBy
        ? `${event} invited your team. Respond by ${dayLabel(a.replyBy, prefs.utcOffsetMinutes)}.`
        : `${event} invited your team. Tap to respond.`,
    }),
  };
}

/** A reminder that a team (its admins) or a player still has something to do before the deadline. */
export function entryDeadlineNotice(a: {
  tournamentId: string;
  teamId: string | null;
  eventName: string;
  kind: ReminderKind;
  missing: Array<"roster" | "payment">;
  deadline: number;
}): Notice {
  const event = a.eventName || "the event";
  const route = a.teamId ? `/tournaments/${a.tournamentId}/respond?team=${a.teamId}` : `/tournaments/${a.tournamentId}`;
  return {
    category: "eventReminders",
    ...(a.teamId && { teamId: a.teamId }),
    route,
    collapseId: `deadline_${a.tournamentId}_${a.teamId ?? "me"}`,
    text: (prefs) =>
      a.kind === "soon"
        ? { title: `Due ${dayLabel(a.deadline, prefs.utcOffsetMinutes)}`, body: `${event}: ${whatsLeft(a.missing)} before the deadline.` }
        : { title: "Entry deadline passed", body: `${event}: you still need to ${whatsLeft(a.missing)}. The organizers can see it's missing.` },
  };
}

/** The deadline passed with teams still missing something: the organizers, once. */
export function organizerDeadlineNotice(a: { tournamentId: string; eventName: string; teams: number }): Notice {
  const event = a.eventName || "Your event";
  return {
    category: "eventReminders",
    route: `/tournaments/${a.tournamentId}?tab=teams`,
    collapseId: `deadline_host_${a.tournamentId}`,
    text: () => ({
      title: "Entry deadline passed",
      body: `${event}: ${a.teams} ${a.teams === 1 ? "entry is" : "entries are"} missing a roster or payment.`,
    }),
  };
}

/** Whether an event's status change is its schedule coming out (before scheduled, now scheduled). */
export function scheduleCameOut(before: Data | undefined, after: Data | undefined): boolean {
  const early = ["draft", "registration", "seeding"];
  return !!before && !!after && early.includes(String(before.status ?? "draft")) && after.status === "scheduled";
}

/** The schedule is out: the entered teams' captains and admins. */
export function scheduleNotice(a: { tournamentId: string; eventName: string }): Notice {
  const event = a.eventName || "Your event";
  return {
    category: "eventChanges",
    route: `/tournaments/${a.tournamentId}?tab=schedule`,
    collapseId: `schedule_${a.tournamentId}`,
    text: () => ({ title: "The schedule is out", body: `${event}: see when and where your team plays.` }),
  };
}

/** Whether a game just became final (its score confirmed or set). */
export function becameFinal(before: Data | undefined, after: Data | undefined): boolean {
  return !!after && after.status === "done" && before?.status !== "done" && typeof after.scoreA === "number" && typeof after.scoreB === "number";
}

/** A final score: both teams. */
export function finalNotice(a: { tournamentId: string; gameId: string; eventName: string; nameA: string; nameB: string; scoreA: number; scoreB: number }): Notice {
  return {
    category: "teamActivity",
    route: `/tournaments/${a.tournamentId}?tab=results`,
    collapseId: `final_${a.tournamentId}_${a.gameId}`,
    text: () => ({
      title: `Final: ${a.nameA} ${a.scoreA}–${a.scoreB} ${a.nameB}`,
      body: a.eventName ? `${a.eventName}` : "Final score",
    }),
  };
}
