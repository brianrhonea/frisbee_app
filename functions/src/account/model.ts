// Pure logic for deleting an account: who takes over a team, and what to
// strip from shared documents. Kept apart from functions.ts so it can be
// unit-tested without Firestore.

export type Data = Record<string, unknown>;

/** What a team doc holds about its members. */
export interface TeamMembers {
  ownerId?: string;
  members?: Record<string, string>;
  memberIds?: string[];
}

/** How long after signing in the user may delete their account. */
export const recentSignInSeconds = 5 * 60;

/** Whether `authTime` (seconds since epoch) is recent enough at `now` (ms). */
export function signedInRecently(authTime: unknown, now: number): boolean {
  return typeof authTime === "number" && now / 1000 - authTime <= recentSignInSeconds;
}

// Coaches, then captains (a group's organizers), then everyone else. A
// legacy "stats" member counts as a player.
const successionOrder = ["coach", "captain", "stats", "player"];

/**
 * Who owns the team once `uid` is gone: the first coach, then captain,
 * then player, in the order they joined (memberIds grows as people join).
 * Undefined when nobody else is on the team.
 */
export function nextOwner(team: TeamMembers, uid: string): string | undefined {
  const others = (team.memberIds ?? []).filter((m) => m !== uid);
  const rank = (m: string) => {
    const i = successionOrder.indexOf(team.members?.[m] ?? "player");
    return i < 0 ? successionOrder.length : i;
  };
  let best: string | undefined;
  for (const m of others) {
    if (best === undefined || rank(m) < rank(best)) best = m;
  }
  return best;
}

/** Event response maps holding one entry per member. */
export const eventResponseFields = ["rsvps", "reactions", "votes"] as const;

/** The event response maps that have an entry for `uid`. */
export function eventResponsesOf(event: Data, uid: string): string[] {
  return eventResponseFields.filter((f) => {
    const m = event[f];
    return typeof m === "object" && m !== null && uid in (m as Data);
  });
}

interface TournamentTeamDoc extends Data {
  id?: string;
  captainId?: string | null;
  playerIds?: string[];
  playerNames?: Record<string, string>;
}

/**
 * A group tournament without `uid` on any of its teams, or null if they
 * weren't on one. Teams they captained lose their captain.
 */
export function tournamentWithout(
  tournament: Data,
  uid: string,
): { teams: TournamentTeamDoc[]; participantIds: string[]; captains: Record<string, string> } | null {
  const teams = (tournament.teams as TournamentTeamDoc[] | undefined) ?? [];
  const onATeam = teams.some((t) => (t.playerIds ?? []).includes(uid) || t.captainId === uid);
  if (!onATeam) return null;
  const next = teams.map((t) => {
    const playerNames = { ...(t.playerNames ?? {}) };
    delete playerNames[uid];
    return {
      ...t,
      captainId: t.captainId === uid ? null : (t.captainId ?? null),
      playerIds: (t.playerIds ?? []).filter((p) => p !== uid),
      playerNames,
    };
  });
  const captains: Record<string, string> = {};
  for (const t of next) {
    if (t.id && t.captainId) captains[t.id] = t.captainId;
  }
  return {
    teams: next,
    participantIds: next.flatMap((t) => t.playerIds),
    captains,
  };
}

/** Name shown for a deleted user in conversations they were in. */
export const deletedUserName = "Deleted user";

/**
 * Storage folder holding the attachments `uid` sent with a message at
 * `messagePath` (a Firestore document path), or undefined for messages
 * that have no attachments in Storage (e.g. meeting chat).
 */
export function attachmentFolder(messagePath: string, uid: string): string | undefined {
  const p = messagePath.split("/");
  // teams/{teamId}/chats/{roomId}/messages/{messageId}
  if (p.length === 6 && p[0] === "teams" && p[2] === "chats" && p[4] === "messages") {
    return `teams/${p[1]}/chats/${p[3]}/${uid}/${p[5]}/`;
  }
  // conversations/{convId}/messages/{messageId}
  if (p.length === 4 && p[0] === "conversations" && p[2] === "messages") {
    return `conversations/${p[1]}/${uid}/${p[3]}/`;
  }
  return undefined;
}

/** Storage folder of a team post's photos, from the post's document path. */
export function postFolder(postPath: string): string | undefined {
  const p = postPath.split("/");
  // teams/{teamId}/posts/{postId}
  if (p.length === 4 && p[0] === "teams" && p[2] === "posts") {
    return `teams/${p[1]}/posts/${p[3]}/`;
  }
  return undefined;
}
