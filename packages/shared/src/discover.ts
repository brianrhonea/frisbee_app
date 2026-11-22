// Discovery helpers both platforms share: team spots left on tournament
// lists (F10) and the Learn guide's lessons and reading progress (F9).
// The app mirrors them (lib/domain/models/discover.dart), checked against
// fixtures/discover by test/discover_fixtures.test.ts.
import type { HostedStatus, TournamentEntryType } from "./tournaments.js";

// ---- Spots left (F10) ------------------------------------------------------

/**
 * Team spots in an event open for registration: [left] of [cap] across
 * its divisions (each division's maxTeams less its accepted teams, its
 * seeds). Computed by the API on `GET /v1/public/tournaments`.
 */
export interface TournamentSpots {
  left: number;
  cap: number;
}

/** A division as the count reads it: its cap and accepted teams (seeds). */
export interface SpotsDivision {
  maxTeams?: unknown;
  seeds?: unknown;
}

/**
 * The spots an event shows, or null when it shows none: only while
 * registration is open, and only for events that take teams (a hat
 * tournament's players aren't capped; its teams are drafted).
 */
export function tournamentSpots(
  t: { status: HostedStatus; entryType: TournamentEntryType },
  divisions: SpotsDivision[],
): TournamentSpots | null {
  if (t.status !== "registration" || t.entryType !== "teams") return null;
  let cap = 0;
  let left = 0;
  for (const d of divisions) {
    const max = typeof d.maxTeams === "number" && Number.isInteger(d.maxTeams) && d.maxTeams > 0 ? d.maxTeams : 0;
    const taken = Array.isArray(d.seeds) ? d.seeds.length : 0;
    cap += max;
    left += Math.max(0, max - taken);
  }
  return cap > 0 ? { left, cap } : null;
}

/** What a list card says: "3 spots left", "1 spot left", or "Full · waitlist". */
export function spotsLabel(s: TournamentSpots): string {
  if (s.left <= 0) return "Full · waitlist";
  return `${s.left} ${s.left === 1 ? "spot" : "spots"} left`;
}

// ---- Learn progress (F9) ---------------------------------------------------

/**
 * The beginner's guide's lessons, in order, by the ids both platforms
 * use (the website's section anchors). The app's learnSections and the
 * website's LearnGuide have one section each, in this order.
 */
export const learnLessons = [
  { id: "basics", title: "The basics" },
  { id: "field", title: "The field" },
  { id: "pull", title: "Starting a point" },
  { id: "moving", title: "Moving the disc" },
  { id: "stall", title: "The stall count" },
  { id: "scoring", title: "Scoring and winning" },
  { id: "turnovers", title: "Turnovers" },
  { id: "defense", title: "Defense" },
  { id: "spirit", title: "Fouls and spirit of the game" },
  { id: "divisions", title: "Divisions and mixed" },
  { id: "words", title: "Words you'll hear" },
  { id: "start", title: "Getting started" },
] as const;

export type LearnLessonId = (typeof learnLessons)[number]["id"];

/**
 * A lesson counts as read once the end of it has stayed on screen this
 * long (so scrolling past doesn't count). The same on both platforms.
 */
export const learnReadAfterMs = 2000;

/** The device storage key for the ids read (localStorage; the app's shared preferences). */
export const learnReadKey = "learn.read";

/** The lessons of [read] that are still in the guide, in the guide's order. */
export function learnReadIds(read: Iterable<string>): LearnLessonId[] {
  const set = new Set(read);
  return learnLessons.filter((l) => set.has(l.id)).map((l) => l.id);
}

/** "3 of 12 read". */
export function learnProgressLabel(read: Iterable<string>): string {
  return `${learnReadIds(read).length} of ${learnLessons.length} read`;
}
