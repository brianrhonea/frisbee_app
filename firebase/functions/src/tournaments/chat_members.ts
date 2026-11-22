// Who is in a hosted tournament's chats with its organizers: the port of
// apps/api/src/tournament_chats/service.ts (organizersOf, captainsOf), so
// the chatMembers trigger keeps them right when an entry changes. Keep the
// two in step; both are tested on the same people
// (test/tournaments/chat_members.test.ts, apps/api/test/tournament_chats.test.ts).

export type Data = Record<string, unknown>;

/** tournamentChatStatuses in packages/shared. */
export const chatStatuses = ["invited", "applied", "accepted", "waitlisted"];

/** tournamentChatSizeMax in packages/shared. */
export const chatSizeMax = 500;

const strings = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
const editors = new Set(["owner", "coach", "captain"]);

/** can(team, perm) in firestore.rules: owners, coaches and captains, or a member granted [perm]. */
export function can(team: Data, uid: string, perm: string): boolean {
  if (!strings(team.memberIds).includes(uid)) return false;
  const role = (team.members as Data | undefined)?.[uid];
  if (typeof role === "string" && editors.has(role)) return true;
  return strings((team.memberPerms as Data | undefined)?.[uid]).includes(perm);
}

export const activeEntry = (e: Data | undefined | null): boolean => !!e && chatStatuses.includes(String(e.status ?? ""));

/** The host's organizers (manages() in the rules). */
export const organizersOf = (host: Data | undefined | null): string[] =>
  host ? strings(host.memberIds).filter((u) => can(host, u, "manageEvents")) : [];

/** An active entry's captains: its captainIds still on the team, and the team's admins. */
export function captainsOf(entry: Data | undefined | null, team: Data | undefined | null): string[] {
  if (!activeEntry(entry) || !team) return [];
  const members = strings(team.memberIds);
  const admins = members.filter((u) => can(team, u, "manageTeam"));
  return [...new Set([...strings(entry!.captainIds).filter((u) => members.includes(u)), ...admins])];
}

export const capMembers = (uids: string[]): string[] => [...new Set(uids)].slice(0, chatSizeMax);

/** Whether an entry's change can change who is in the chats: its status in or out, or its captains. */
export function entryChatChange(before: Data | undefined, after: Data | undefined): boolean {
  if (activeEntry(before) !== activeEntry(after)) return true;
  if (!activeEntry(after)) return false;
  const a = strings(before?.captainIds).join(",");
  const b = strings(after?.captainIds).join(",");
  return a !== b;
}
