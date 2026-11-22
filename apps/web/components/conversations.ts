// A member's conversations (Conversation in the app): what each one is to
// them (inbox, request, archived, unread), shared by Messages and the
// Chats tab's bubble (useUnreadChats).
import type { Doc } from "@/lib/live";

/** conversations/{id} (Conversation in the app). */
export interface Conversation {
  /** "tournament": a hosted tournament's chat with its organizers, run by the server (no add, leave or rename). */
  kind?: "direct" | "group" | "tournament";
  /** For a tournament chat: the hosted tournament. */
  tournamentId?: string;
  name?: string;
  createdBy?: string;
  participants?: string[];
  names?: Record<string, string>;
  lastMessage?: string;
  lastMessageAt?: string | null;
  lastSenderId?: string;
  readAt?: Record<string, string>;
  status?: "accepted" | "request" | "declined";
  requestedOf?: string;
}
/** users/{uid}/dmReads/{id}: the member's own read time, archive and clear. */
export interface Mine {
  readAt?: string;
  archivedAt?: string;
  clearedAt?: string;
}

export const ms = (iso?: string | null) => (iso ? Date.parse(iso) : Number.NaN);
export const isGroup = (c: Doc<Conversation>) => c.kind === "group" || c.id.startsWith("g-");

/** The model's rules (Conversation in the app), for the signed-in [me]. */
export function describe(c: Doc<Conversation>, mine: Mine | undefined, me: string) {
  const last = ms(c.lastMessageAt);
  const quietSince = (at?: string) => !!at && (Number.isNaN(last) || last <= ms(at));
  const requestForMe = c.status === "request" && c.requestedOf === me;
  const declinedByMe = c.status === "declined" && c.requestedOf === me;
  const archived = quietSince(mine?.archivedAt);
  const cleared = quietSince(mine?.clearedAt);
  const listed = !Number.isNaN(last) || isGroup(c);
  const shared = ms(c.readAt?.[me]);
  const own = ms(mine?.readAt);
  const read = Math.max(Number.isNaN(shared) ? 0 : shared, Number.isNaN(own) ? 0 : own);
  const unread = !Number.isNaN(last) && !!c.lastSenderId && c.lastSenderId !== me && read < last;
  const others = (c.participants ?? []).filter((u) => u !== me);
  const title = isGroup(c) ? c.name || "Group" : c.names?.[others[0] ?? ""] || "Player";
  return {
    title,
    others,
    requestForMe,
    pendingFromMe: c.status !== "accepted" && !!c.requestedOf && c.requestedOf !== me,
    inInbox: listed && !requestForMe && !declinedByMe && !archived && !cleared,
    inRequests: requestForMe && listed,
    inArchive: archived && !cleared,
    unread: unread && !cleared,
    seen: c.lastSenderId === me && others.length === 1 && !Number.isNaN(last) && ms(c.readAt?.[others[0]!]) >= last,
  };
}
