// Hosted tournaments on team schedules: once a host accepts a team's
// entry, the tournament appears as a Tournament event on that team's
// schedule, linked to the tournament page (the event's `tournamentId`).
// It follows the tournament's name, dates and place, and comes off the
// schedule if the team is no longer accepted.

export type Data = Record<string, unknown>;

/** The event id a tournament gets on each accepted team's schedule. */
export const eventIdFor = (tournamentId: string): string => `tournament_${tournamentId}`;

/** Whether an entry (`tournaments/{id}/entries/{teamId}`) is in. */
export const isAccepted = (entry: Data | undefined): boolean => entry?.status === "accepted";

/** What a change to an entry does to the team's schedule. */
export type EntryChange = "add" | "remove" | null;

export function entryChange(before: Data | undefined, after: Data | undefined): EntryChange {
  const was = isAccepted(before);
  const is = isAccepted(after);
  if (is && !was) return "add";
  if (was && !is) return "remove";
  return null;
}

const clip = (s: unknown, max: number): string => (typeof s === "string" ? s.trim().slice(0, max) : "");

/**
 * The event's details from the tournament: what the team's schedule shows
 * and what follows the tournament when the host edits it.
 */
export function eventDetails(tournament: Data): Data {
  const startsAt = tournament.startsOn ?? null;
  const ends = tournament.endsOn ?? null;
  const host = clip(tournament.hostName, 80);
  return {
    title: clip(tournament.name, 100) || "Tournament",
    type: "tournament",
    startsAt,
    // Rules require an end on or after the start.
    endsAt: ends !== null && startsAt !== null && millis(ends) >= millis(startsAt) ? ends : null,
    location: clip(tournament.location, 200),
    notes: host ? `Hosted by ${host}. Open the tournament page for divisions, schedule and results.` : "",
  };
}

/** The whole event for a team whose entry was just accepted. */
export function newEvent(tournamentId: string, tournament: Data, team: Data | undefined): Data {
  return {
    ...eventDetails(tournament),
    tournamentId,
    poll: null,
    public: false,
    rsvps: {},
    reactions: {},
    votes: {},
    // Schools and clubs say who sees each event; this one is for everyone.
    ...(team?.kind === "organization" ? { audience: ["everyone"] } : {}),
  };
}

/**
 * A team's own record of a tournament it's entered, at
 * `teams/{teamId}/tournamentEntries/{tournamentId}`: entries don't say
 * which team they're for in a field, so this is how a team lists the
 * tournaments it plays in. Null when the entry is gone.
 */
export function entryRecord(tournament: Data, entry: Data | undefined): Data | null {
  if (!entry) return null;
  return {
    name: clip(tournament.name, 100) || "Tournament",
    hostId: typeof tournament.hostId === "string" ? tournament.hostId : "",
    hostName: clip(tournament.hostName, 80),
    startsOn: tournament.startsOn ?? null,
    endsOn: tournament.endsOn ?? null,
    location: clip(tournament.location, 200),
    status: typeof entry.status === "string" ? entry.status : "applied",
  };
}

/** What a team's records of a tournament need when the host edits it. */
export function recordUpdate(before: Data, after: Data): Data | null {
  const was = entryRecord(before, {});
  const now = entryRecord(after, {});
  if (!was || !now) return null;
  const update: Data = {};
  for (const key of ["name", "hostName", "startsOn", "endsOn", "location"]) {
    if (!same(was[key], now[key])) update[key] = now[key];
  }
  return Object.keys(update).length > 0 ? update : null;
}

/** The detail fields that changed between two versions of a tournament. */
export function changedDetails(before: Data, after: Data): Data | null {
  const was = eventDetails(before);
  const now = eventDetails(after);
  const update: Data = {};
  for (const key of Object.keys(now)) {
    if (!same(was[key], now[key])) update[key] = now[key];
  }
  return Object.keys(update).length > 0 ? update : null;
}

function same(a: unknown, b: unknown): boolean {
  const ma = millisOrNull(a);
  const mb = millisOrNull(b);
  if (ma !== null || mb !== null) return ma === mb;
  return a === b;
}

function millisOrNull(v: unknown): number | null {
  if (v instanceof Date) return v.getTime();
  if (v && typeof v === "object" && "toMillis" in v && typeof (v as { toMillis: unknown }).toMillis === "function") {
    return (v as { toMillis: () => number }).toMillis();
  }
  return null;
}

function millis(v: unknown): number {
  return millisOrNull(v) ?? Number.NaN;
}
