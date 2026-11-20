// "Download your data" (`GET /v1/me/export`, Settings › Account on both
// clients): a JSON file of what Stall 10 keeps about the caller. Built by
// apps/api/src/export with the caller from the ID token. Their own content
// in full; other people only as far as needed to make sense of it (a
// team's name, a conversation's other names), never their messages,
// answers, likes or details.

/** How often one person may download their data (the API keeps the time in `limits/{uid}`). */
export const dataExportIntervalMs = 10 * 60_000;

/** The most of each kind one export holds; a section that hit its cap says `truncated`. */
export const dataExportLimits = {
  posts: 2000,
  comments: 5000,
  messages: 10000,
  follows: 2000,
  teams: 200,
  /** Events and meetings read per team for the caller's answers. */
  eventsPerTeam: 1000,
  conversations: 1000,
  personalEvents: 2000,
  rosterSpots: 500,
} as const;

/** What "Download your data" gives, as both apps say it (downloadDataDescription in download_data_group.dart). */
export const downloadDataDescription =
  "A JSON file of your account, profile, personal details, posts, comments, messages you sent, follows, teams, RSVPs and stats. Once every 10 minutes.";

/** The file's name, by the day it was made (UTC). */
export const dataExportFileName = (exportedAt: Date) => `stall10-data-${exportedAt.toISOString().slice(0, 10)}.json`;

type Json = Record<string, unknown>;

/** One kind of record, up to its dataExportLimits cap. */
export interface DataExportSection<T> {
  items: T[];
  /** True when there were more than the cap; the newest or first ones by id are kept. */
  truncated: boolean;
}

/** Where a message the caller sent lives. */
export type DataExportMessagePlace =
  | { kind: "direct"; conversationId: string }
  | { kind: "teamChat"; teamId: string; roomId: string }
  | { kind: "meeting"; teamId: string; meetingId: string }
  | { kind: "other"; path: string };

export interface DataExportMessage {
  id: string;
  place: DataExportMessagePlace;
  text?: string;
  createdAt?: string;
  editedAt?: string;
  /** Files sent with it: name, type and size, and the Storage path. */
  attachments?: Json[];
  /** The id of the message it answered (not that message's text). */
  replyToId?: string;
}

export interface DataExportComment {
  id: string;
  postId: string;
  body?: string;
  parentId?: string;
  createdAt?: string;
  editedAt?: string;
}

export interface DataExportTeam {
  id: string;
  name: string;
  kind: "team" | "community" | "organization";
  /** owner, coach, captain, player or stats. */
  tier: string;
  /** The names of the custom roles the caller has. */
  roles: string[];
  /** The permissions those roles give. */
  permissions: string[];
  statKeeper: boolean;
}

/** The caller's own answer to one team event or meeting. */
export interface DataExportResponse {
  teamId: string;
  teamName: string;
  kind: "event" | "meeting";
  id: string;
  title?: string;
  startsAt?: string;
  /** going, maybe or notGoing (rsvps). */
  rsvp?: unknown;
  /** Their note with it (rsvpNotes). */
  note?: unknown;
  /** Their poll votes (votes) and reaction (reactions). */
  votes?: unknown;
  reaction?: unknown;
}

export interface DataExportConversation {
  id: string;
  kind: string;
  /** The group's name, for a group conversation. */
  name?: string;
  /** Everyone in it, with the name it shows for them. */
  participants: { uid: string; name?: string }[];
}

export interface DataExportRosterSpot {
  teamId: string;
  name?: string;
  number?: number;
  position?: string;
}

/** The whole file. Dates are ISO 8601 strings. */
export interface DataExport {
  format: "stall10-data-export";
  version: 1;
  exportedAt: string;
  uid: string;
  /** The sign-in record: email, name, when the account was made. */
  account: { email?: string; name?: string; photoUrl?: string; createdAt?: string };
  /** users/{uid}: the private account doc (message settings, read receipts, …). */
  user: Json | null;
  /** profiles/{uid}: the profile others see, with its stats when kept. */
  profile: Json | null;
  /** A private profile's details (profiles/{uid}/private/details). */
  privateDetails: Json | null;
  /**
   * Personal details (legal name, birth date, phone, address, guardian),
   * decrypted; null when none were given, "unavailable" when this server
   * can't read them (no key).
   */
  personalDetails: Json | null | "unavailable";
  notificationSettings: Json | null;
  follows: DataExportSection<Json>;
  posts: DataExportSection<Json>;
  comments: DataExportSection<DataExportComment>;
  messages: DataExportSection<DataExportMessage>;
  conversations: DataExportSection<DataExportConversation>;
  teams: DataExportSection<DataExportTeam>;
  responses: DataExportSection<DataExportResponse>;
  personalEvents: DataExportSection<Json>;
  rosterSpots: DataExportSection<DataExportRosterSpot>;
}
