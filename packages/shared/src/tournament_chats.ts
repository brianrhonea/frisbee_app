// A hosted tournament's chats with its organizers: one Captains' channel
// (every entered team's captains and the organizers) and a private thread
// per team (that team's captains and the organizers). Both are
// conversations of kind "tournament" in the Messages inbox; only the
// server sets who is in them (no adding, leaving or renaming), from the
// entries: recomputed when someone opens one from the tournament's page
// (the open endpoints) and when an entry changes (the
// tournaments-chatMembers function). Opening it from the inbox doesn't, so
// someone who stops organizing or leaves a team reads on until the next.

/**
 * Entries whose captains are in the chats: from applying on. Invited
 * teams aren't, so an invite can't put a team's admins in a chat past
 * their message settings; declined and withdrawn teams drop out.
 */
export const tournamentChatStatuses = ["applied", "accepted", "waitlisted"] as const;

/** Most people in one tournament chat (organizers first). */
export const tournamentChatSizeMax = 500;

/** Longest chat name (validString(name, 60) on conversations). */
const chatNameMax = 60;
const clipName = (s: string) => (s.length > chatNameMax ? `${s.slice(0, chatNameMax - 1)}…` : s);

/** "Spring Fling · Captains". */
export const captainsChatName = (tournament: string) => clipName(`${tournament.trim() || "Tournament"} · Captains`);

/** "Haze · Spring Fling organizers". */
export const teamChatName = (team: string, tournament: string) =>
  clipName(`${team.trim() || "Team"} · ${tournament.trim() || "Tournament"} organizers`);

export type TournamentChatKind = "captains" | "team";

/** What the open endpoints answer: the conversation to show. */
export interface TournamentChatResult {
  id: string;
}

export const tournamentChatPaths = {
  /** POST: the Captains' channel, for organizers and entered teams' captains. */
  captains: (t: string) => `/v1/tournaments/${t}/chats/captains`,
  /** POST: a team's private thread with the organizers. */
  team: (t: string, team: string) => `/v1/tournaments/${t}/chats/teams/${team}`,
};
