/** A team chat room as the inbox needs it (teams/{id}/chats/{room}). */
export interface InboxRoom {
  id: string;
  name?: string;
  kind?: "text" | "voice" | string;
  /** When its last message was sent (ChatRoom.lastAt): a time, never the text. */
  lastAt?: string | null;
}

/** One team's chat as the inbox lists it (TeamChatSummary in the app). */
export interface TeamChatSummary<R extends InboxRoom = InboxRoom> {
  /** The text rooms the user can read, in the order given. */
  rooms: R[];
  /** Those with a message the user hasn't read, newest first. */
  unread: R[];
  /** When the newest room last had a message; null before any. */
  lastAt: string | null;
  /** The room a click opens: the only unread one, else the newest, else the first. */
  open: R | null;
  /** "Cam mentioned you: …", "New in #general and #carpool", "Team chat" or "No messages yet". */
  subtitle: string;
  /** The newest @mention of the user they haven't read, if any. */
  mention: ChatMention | null;
}

/**
 * An @mention of the user in a team room: their notification feed entry
 * (users/{uid}/notifications/mention_{teamId}_{roomId}, `mention: true`).
 * [text] is its body ("Cam mentioned you: …"); [personal] when they were
 * named or reached by role, not @everyone.
 */
export interface ChatMention {
  roomId: string;
  text: string;
  at: string;
  personal: boolean;
}

const time = (iso?: string | null) => (iso ? Date.parse(iso) : Number.NaN);

/** A room's name as Discord writes channels (ChatRoom.handle): lowercase, dashes for spaces. */
export const roomHandle = (name?: string) => (name ?? "").trim().toLowerCase().replace(/\s+/g, "-");

/** Whether [room] has a message newer than [readAt] (null: never read). Voice channels never do. */
export function roomUnread(room: InboxRoom, readAt?: string | null): boolean {
  const last = time(room.lastAt);
  if (room.kind === "voice" || Number.isNaN(last)) return false;
  const read = time(readAt);
  return Number.isNaN(read) || last > read;
}

/**
 * A team's chat in the inbox, from the rooms the user can read
 * ([readable]) and their read times ([reads], room id → time). Checked on
 * fixtures/team_chats/summary.json, which the app writes.
 */
export function teamChatSummary<R extends InboxRoom>(
  readable: R[],
  reads: Record<string, string | null | undefined>,
  /** Muted rooms never count as unread: muting hides the bubble too. */
  muted: (roomId: string) => boolean = () => false,
  /**
   * The user's @mentions in this team. One after their read of the room
   * makes it unread and says so, even in a muted room when it names them
   * (an @everyone in a muted room doesn't).
   */
  mentions: ChatMention[] = [],
): TeamChatSummary<R> {
  const rooms = readable.filter((r) => r.kind !== "voice");
  const counted = mentions.filter((m) => {
    const read = time(reads[m.roomId]);
    const at = time(m.at);
    if (Number.isNaN(at) || !rooms.some((r) => r.id === m.roomId)) return false;
    if (!Number.isNaN(read) && at <= read) return false;
    return m.personal || !muted(m.roomId);
  });
  let mention: ChatMention | null = null;
  for (const m of counted) if (mention === null || time(m.at) > time(mention.at)) mention = m;
  const unread = rooms
    .filter((r) => (roomUnread(r, reads[r.id]) && !muted(r.id)) || counted.some((m) => m.roomId === r.id))
    .sort((a, b) => time(b.lastAt) - time(a.lastAt));
  let newest: R | null = null;
  for (const r of rooms) {
    const at = time(r.lastAt);
    if (!Number.isNaN(at) && (newest === null || at > time(newest.lastAt))) newest = r;
  }
  const open = mention
    ? (rooms.find((r) => r.id === mention.roomId) ?? null)
    : unread.length === 1
      ? unread[0]
      : (newest ?? rooms[0] ?? null);
  let subtitle: string;
  if (mention) {
    subtitle = mention.text;
  } else if (unread.length > 0) {
    const names = unread.map((r) => `#${roomHandle(r.name)}`);
    subtitle = `New in ${names.length <= 2 ? names.join(" and ") : `${names.slice(0, 2).join(", ")} and ${names.length - 2} more`}`;
  } else {
    subtitle = newest ? "Team chat" : "No messages yet";
  }
  return { rooms, unread, lastAt: newest?.lastAt ?? null, open, subtitle, mention };
}
