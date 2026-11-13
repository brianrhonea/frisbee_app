// Notices for leagues and hat tournaments where players sign up: the
// captains' draft (it started, it's your pick, the teams are set) and the
// host's decision on a signup. Pure, like model.ts, so it's unit-tested in
// test/notifications/league.test.ts.

import { onTheClock, type Pick } from "../tournaments/draft_model";
import type { Data, Notice } from "./model";

/** One notice and who gets it. */
export interface Delivery {
  uids: string[];
  notice: Notice;
}

interface Captain {
  uid: string;
  name: string;
}

const captainsOf = (d: Data): Captain[] =>
  Array.isArray(d.captains)
    ? (d.captains as Data[]).map((c) => ({ uid: String(c.uid ?? ""), name: String(c.name ?? "") || "Captain" }))
    : [];
const picksOf = (d: Data): Pick[] => (Array.isArray(d.picks) ? (d.picks as Pick[]) : []);
const poolOf = (d: Data): string[] => Object.keys((d.pool ?? {}) as Record<string, unknown>);

const clockOf = (d: Data | undefined): string | null =>
  d && d.status === "live"
    ? onTheClock(
        captainsOf(d).map((c) => c.uid),
        picksOf(d),
        poolOf(d).length,
      )
    : null;

/**
 * Who to tell what after a draft doc changes:
 * - it starts: each captain ("you're a captain", the first one also that
 *   they pick first) and every player in the pool;
 * - the turn passes (a pick, an undo, a resume): the captain now on the
 *   clock, every time, so the phone buzzes;
 * - the host finishes it: everyone, with the team they're on.
 * Cancelling (the doc is deleted) tells nobody.
 */
export function draftDeliveries(a: {
  tournamentId: string;
  divisionId: string;
  eventName: string;
  before: Data | undefined;
  after: Data | undefined;
}): Delivery[] {
  const { tournamentId, divisionId, before, after } = a;
  if (!after) return [];
  const event = a.eventName || "The draft";
  const board = `/tournaments/${tournamentId}/live-draft/${divisionId}`;
  const collapseId = `draft_${tournamentId}_${divisionId}`;
  const captains = captainsOf(after);
  const nameOf = (uid: string) => captains.find((c) => c.uid === uid)?.name ?? "A captain";
  const base = { category: "teamActivity" as const, route: board, collapseId };

  if (!before && after.status === "live") {
    const first = clockOf(after);
    return [
      ...captains.map((c) => ({
        uids: [c.uid],
        notice: {
          ...base,
          pushId: "start",
          text: () => ({
            title: `${event}: you're a captain`,
            body:
              c.uid === first
                ? "The draft is live and you pick first."
                : `The draft is live. ${nameOf(first ?? "")} picks first.`,
          }),
        },
      })),
      {
        uids: poolOf(after),
        notice: {
          ...base,
          text: () => ({
            title: `${event}: the draft is live`,
            body: "Watch the captains pick the teams.",
          }),
        },
      },
    ];
  }

  if (after.status === "finished" && before?.status !== "finished") {
    const picks = picksOf(after);
    return captains.map((c) => ({
      uids: [c.uid, ...picks.filter((p) => p.captainId === c.uid).map((p) => p.uid)],
      notice: {
        ...base,
        route: `/tournaments/${tournamentId}`,
        pushId: "finished",
        text: () => ({
          title: `${event}: the teams are set`,
          body: `You're on Team ${c.name}.`,
        }),
      },
    }));
  }

  const clock = clockOf(after);
  if (clock && clock !== clockOf(before)) {
    const seconds = Number(after.pickSeconds ?? 0);
    return [
      {
        uids: [clock],
        notice: {
          ...base,
          // Every turn buzzes; the feed keeps one entry per draft.
          pushId: String(picksOf(after).length),
          text: () => ({
            title: `${event}: your pick`,
            body:
              seconds > 0
                ? `You're on the clock: ${seconds} seconds to pick a player.`
                : "You're on the clock. Pick a player.",
          }),
        },
      },
    ];
  }
  return [];
}

/** The host accepted, waitlisted or declined a player's signup. */
export function signupDecisionNotice(a: {
  tournamentId: string;
  eventName: string;
  before: Data | undefined;
  after: Data | undefined;
}): Notice | null {
  const status = a.after?.status;
  if (!a.before || status === a.before.status) return null;
  const event = a.eventName || "the event";
  const body = {
    accepted: `You're in ${event}. You'll be drafted onto a team.`,
    waitlisted: `You're on the waitlist for ${event}.`,
    declined: `Your signup for ${event} wasn't accepted this time.`,
  }[String(status)];
  if (!body) return null;
  return {
    category: "teamActivity",
    route: `/tournaments/${a.tournamentId}`,
    collapseId: `signup_${a.tournamentId}`,
    text: () => ({ title: status === "accepted" ? "You're in" : "Signup update", body }),
  };
}
