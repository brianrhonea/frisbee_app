// Pure notification logic: who gets what, and how it's worded. No Firebase
// calls here, so it's unit-tested in test/notifications.

/** NotificationCategory in lib/domain/models/notification.dart. */
export const categories = [
  "chat",
  "directMessages",
  "eventChanges",
  "eventReminders",
  "teamActivity",
  "meetings",
  "posts",
] as const;
export type Category = (typeof categories)[number];

/** users/{uid}/settings/notifications. Missing means on. */
export interface Prefs {
  categories?: Record<string, unknown>;
  teams?: Record<string, Record<string, unknown> | undefined>;
  mutedRooms?: unknown[];
  utcOffsetMinutes?: number;
}

export interface TeamDoc {
  name?: string;
  ownerId?: string;
  members?: Record<string, string>;
  memberIds?: string[];
  deletingAt?: unknown;
}

export interface RoomDoc {
  name?: string;
  readRoles?: string[];
  readUsers?: string[];
}

export type Data = Record<string, unknown>;

/** Whether [prefs] allow [category], after the team override and room mute. */
export function wants(
  prefs: Prefs | undefined,
  category: Category,
  teamId?: string,
  roomId?: string,
): boolean {
  if (teamId && roomId && prefs?.mutedRooms?.includes(`${teamId}/${roomId}`)) {
    return false;
  }
  if (teamId && category !== "directMessages") {
    const team = prefs?.teams?.[teamId]?.[category];
    if (typeof team === "boolean") return team;
  }
  const global = prefs?.categories?.[category];
  return typeof global === "boolean" ? global : true;
}

/**
 * Members who can read [room]: the owner, its roles and its people. Mirrors
 * canReadRoom in firestore.rules; a legacy "stats" member is a player.
 */
export function roomReaders(team: TeamDoc, room: RoomDoc): string[] {
  const members = team.members ?? {};
  return Object.keys(members).filter((uid) => {
    const role = members[uid] === "stats" ? "player" : members[uid];
    return (
      role === "owner" ||
      (room.readRoles ?? []).includes(role) ||
      (room.readUsers ?? []).includes(uid)
    );
  });
}

/** TeamEvent.toEditableMap(); RSVPs, reactions and votes aren't news. */
export const editableEventFields = [
  "title",
  "type",
  "startsAt",
  "endsAt",
  "location",
  "notes",
  "poll",
] as const;

export type EventChange = "created" | "updated" | "deleted";

export function eventChange(before?: Data, after?: Data): EventChange | null {
  if (!before && after) return "created";
  if (before && !after) return "deleted";
  if (before && after && changedFields(before, after).length > 0) {
    return "updated";
  }
  return null;
}

export function changedFields(before: Data, after: Data): string[] {
  return editableEventFields.filter((f) => !same(before[f], after[f]));
}

interface HasMillis {
  toMillis(): number;
}
const hasMillis = (v: unknown): v is HasMillis =>
  typeof v === "object" && v !== null && typeof (v as HasMillis).toMillis === "function";

/** Epoch millis of a Firestore Timestamp, Date or number. */
export function millis(v: unknown): number | undefined {
  if (hasMillis(v)) return v.toMillis();
  if (v instanceof Date) return v.getTime();
  if (typeof v === "number") return v;
  return undefined;
}

/** Deep equality for Firestore values; null and missing are the same. */
export function same(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a == null || b == null) return a == null && b == null;
  const ma = millis(a);
  if (ma !== undefined && typeof a !== "number") return ma === millis(b);
  if (Array.isArray(a)) {
    return Array.isArray(b) && a.length === b.length && a.every((v, i) => same(v, b[i]));
  }
  if (typeof a === "object" && typeof b === "object") {
    const ra = a as Data;
    const rb = b as Data;
    const keys = new Set([...Object.keys(ra), ...Object.keys(rb)]);
    return [...keys].every((k) => same(ra[k], rb[k]));
  }
  return false;
}

const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/**
 * "Sat, Nov 1 at 6:00 PM" in the user's offset (the app records it at
 * sign-in); UTC, and says so, when there's none.
 */
export function formatWhen(ms: number, offsetMinutes?: number): string {
  const d = new Date(ms + (offsetMinutes ?? 0) * 60_000);
  const h = d.getUTCHours();
  const time = `${h % 12 || 12}:${String(d.getUTCMinutes()).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
  const zone = offsetMinutes === undefined ? " UTC" : "";
  return `${days[d.getUTCDay()]}, ${months[d.getUTCMonth()]} ${d.getUTCDate()} at ${time}${zone}`;
}

/** messagePreview in lib/domain/models/direct_message.dart. */
export function messagePreview(message: Data): string {
  const text = String(message.text ?? "").trim().replace(/\s+/g, " ");
  if (text) return text.length > 120 ? `${text.slice(0, 117)}…` : text;
  const files = Array.isArray(message.attachments) ? message.attachments : [];
  if (files.length === 0) return "";
  const images = files.every((f) => String((f as Data)?.contentType ?? "").startsWith("image/"));
  if (images) return files.length === 1 ? "📷 Photo" : `📷 ${files.length} photos`;
  return files.length === 1 ? "📎 File" : `📎 ${files.length} files`;
}

/** What one recipient is sent. */
export interface Text {
  title: string;
  body: string;
}

export interface Notice {
  category: Category;
  teamId?: string;
  roomId?: string;
  route: string;
  /**
   * Feed entry to fold repeats into (one per room or conversation); a new
   * entry each time when unset. Also groups the pushes on the device.
   */
  collapseId?: string;
  /** Worded per recipient: their time zone, and how many are unread. */
  text(prefs: Prefs, count: number): Text;
}

const eventTypes: Record<string, string> = {
  practice: "Practice",
  game: "Game",
  tournament: "Tournament",
  scrimmage: "Scrimmage",
  workout: "Workout",
  social: "Social",
  other: "Event",
  pickup: "Pickup",
};
const typeLabel = (e: Data) => eventTypes[String(e.type)] ?? "Event";
const eventTitle = (e: Data) => String(e.title ?? "") || typeLabel(e);

function whenAndWhere(e: Data, prefs: Prefs): string {
  const start = millis(e.startsAt);
  const parts = [start === undefined ? "" : formatWhen(start, prefs.utcOffsetMinutes)];
  const location = String(e.location ?? "").trim();
  if (location) parts.push(location);
  return parts.filter(Boolean).join(" · ");
}

export function chatNotice(a: {
  teamId: string;
  roomId: string;
  teamName: string;
  roomName: string;
  message: Data;
}): Notice {
  const line = `${String(a.message.authorName ?? "Someone")}: ${messagePreview(a.message)}`;
  return {
    category: "chat",
    teamId: a.teamId,
    roomId: a.roomId,
    route: `/teams/${a.teamId}/chats/${a.roomId}`,
    collapseId: `chat_${a.teamId}_${a.roomId}`,
    text: (_, count) => ({
      title: `${a.roomName} · ${a.teamName}`,
      body: count > 1 ? `${count} new messages · ${line}` : line,
    }),
  };
}

export function directMessageNotice(a: { conversationId: string; message: Data }): Notice {
  const preview = messagePreview(a.message);
  return {
    category: "directMessages",
    route: `/messages/${a.conversationId}`,
    collapseId: `dm_${a.conversationId}`,
    text: (_, count) => ({
      title: String(a.message.authorName ?? "New message"),
      body: count > 1 ? `${count} new messages · ${preview}` : preview,
    }),
  };
}

/** What changed, for the body of an "updated" notice. */
function changeSummary(before: Data, after: Data): string {
  const fields = changedFields(before, after);
  const time = fields.includes("startsAt") || fields.includes("endsAt");
  const place = fields.includes("location");
  if (time && place) return "New time and place";
  if (time) return "New time";
  if (place) return "New place";
  if (fields.length === 1 && fields[0] === "poll") return "Poll changed";
  return "Details changed";
}

export function eventChangeNotice(a: {
  change: EventChange;
  teamId: string;
  eventId: string;
  teamName: string;
  before?: Data;
  after?: Data;
}): Notice {
  const event = (a.after ?? a.before)!;
  const name = eventTitle(event);
  const route =
    a.change === "deleted"
      ? `/teams/${a.teamId}/events`
      : `/team-events/${a.teamId}/${a.eventId}`;
  return {
    category: "eventChanges",
    teamId: a.teamId,
    route,
    collapseId: `event_${a.teamId}_${a.eventId}`,
    text: (prefs) => {
      const where = whenAndWhere(event, prefs);
      switch (a.change) {
        case "created":
          return { title: `${a.teamName}: new ${typeLabel(event).toLowerCase()}`, body: `${name} · ${where}` };
        case "deleted":
          return { title: `${a.teamName}: ${name} cancelled`, body: `Was ${where}` };
        case "updated":
          return {
            title: `${a.teamName}: ${name} updated`,
            body: `${changeSummary(a.before!, a.after!)} · ${where}`,
          };
      }
    },
  };
}

export function reminderNotice(a: {
  event: Data;
  route: string;
  teamId?: string;
  teamName?: string;
}): Notice {
  return {
    category: "eventReminders",
    teamId: a.teamId,
    route: a.route,
    text: (prefs) => ({
      title: `Tomorrow: ${eventTitle(a.event)}`,
      body: [a.teamName, whenAndWhere(a.event, prefs)].filter(Boolean).join(" · "),
    }),
  };
}

export function playNotice(a: {
  created: boolean;
  teamId: string;
  playId: string;
  teamName: string;
  play: Data;
}): Notice {
  const name = String(a.play.name ?? "") || "Untitled play";
  return {
    category: "teamActivity",
    teamId: a.teamId,
    route: `/teams/${a.teamId}/plays/${a.playId}`,
    collapseId: `play_${a.teamId}_${a.playId}`,
    text: () => ({
      title: `${a.teamName}: ${a.created ? "new play" : "play updated"}`,
      body: name,
    }),
  };
}

/** Team members a reminder goes to: everyone who hasn't said they can't go. */
export function reminderRecipients(team: TeamDoc, event: Data): string[] {
  const rsvps = (event.rsvps ?? {}) as Record<string, unknown>;
  return (team.memberIds ?? []).filter((uid) => rsvps[uid] !== "notGoing");
}

/** Meeting notices go to the meeting page, or straight to its room. */
const meetingRoute = (teamId: string, meetingId: string) => `/team-meetings/${teamId}/${meetingId}`;

export function meetingInviteNotice(a: {
  teamId: string;
  meetingId: string;
  teamName: string;
  meeting: Data;
}): Notice {
  const title = String(a.meeting.title ?? "") || "Meeting";
  return {
    category: "meetings",
    teamId: a.teamId,
    route: meetingRoute(a.teamId, a.meetingId),
    collapseId: `meeting_${a.teamId}_${a.meetingId}`,
    text: (prefs) => ({
      title: `${a.teamName}: you're invited to a meeting`,
      body: [title, whenAndWhere(a.meeting, prefs)].filter(Boolean).join(" · "),
    }),
  };
}

/**
 * The meeting is live. Its feed id starts with `meetingStarted_`, which the
 * app looks for to pop up a Join prompt (MeetingAlertsViewModel).
 */
export function meetingStartedNotice(a: {
  teamId: string;
  meetingId: string;
  teamName: string;
  meeting: Data;
}): Notice {
  const title = String(a.meeting.title ?? "") || "Your meeting";
  return {
    category: "meetings",
    teamId: a.teamId,
    route: `${meetingRoute(a.teamId, a.meetingId)}/room`,
    collapseId: `meetingStarted_${a.teamId}_${a.meetingId}`,
    text: () => ({ title: `${title} has started`, body: `${a.teamName} · Tap to join` }),
  };
}

export function meetingCancelledNotice(a: {
  teamId: string;
  meetingId: string;
  teamName: string;
  meeting: Data;
}): Notice {
  const title = String(a.meeting.title ?? "") || "Meeting";
  return {
    category: "meetings",
    teamId: a.teamId,
    route: `/teams/${a.teamId}/events`,
    collapseId: `meeting_${a.teamId}_${a.meetingId}`,
    text: (prefs) => ({
      title: `${a.teamName}: ${title} cancelled`,
      body: `Was ${whenAndWhere(a.meeting, prefs)}`,
    }),
  };
}

// ---- Follows and posts -----------------------------------------------------

/**
 * FollowTarget keys in lib/domain/models/follow.dart: "{type}_{targetId}".
 * Group tournaments are "tournament_{groupId}_{tournamentId}".
 */
export const followKey = {
  user: (uid: string) => `user_${uid}`,
  team: (teamId: string) => `team_${teamId}`,
};

/** Whose followers hear about a post: its author or team, and its tournament. */
export function followKeys(a: { authorId?: string; teamId?: string; post: Data }): string[] {
  const keys = [
    a.teamId ? followKey.team(a.teamId) : a.authorId ? followKey.user(a.authorId) : "",
    typeof a.post.tournamentKey === "string" ? a.post.tournamentKey : "",
  ];
  return [...new Set(keys.filter(Boolean))];
}

/**
 * Followers to notify: deduped, without the author, and, for posts only
 * members may read, only members.
 */
export function postRecipients(followers: string[], authorId: string, readers?: string[]): string[] {
  const allowed = readers ? new Set(readers) : undefined;
  return [...new Set(followers)].filter((uid) => uid !== authorId && (!allowed || allowed.has(uid)));
}

const workoutActivities: Record<string, string> = {
  run: "run",
  sprints: "sprint session",
  throwing: "throwing session",
  gym: "gym session",
  agility: "agility session",
  mobility: "mobility session",
  other: "workout",
};

/** "45 min run · 8 km", or the post's text. */
export function postPreview(post: Data): string {
  const workout = post.kind === "workout" ? (post.workout as Data | undefined) : undefined;
  const text = String(post.body ?? "").trim().replace(/\s+/g, " ");
  if (workout) {
    const minutes = Number(workout.durationMinutes ?? 0);
    const activity = workoutActivities[String(workout.activity)] ?? "workout";
    const distance = typeof workout.distanceKm === "number" ? ` · ${workout.distanceKm} km` : "";
    const summary = `${minutes > 0 ? `${minutes} min ` : ""}${activity}${distance}`;
    return text ? `${summary} · ${clip(text, 90)}` : summary;
  }
  const title = String(post.title ?? "").trim();
  const line = [title, text].filter(Boolean).join(": ");
  if (line) return clip(line, 120);
  const images = Array.isArray(post.images) ? post.images.length : 0;
  return images > 1 ? `📷 ${images} photos` : "📷 Photo";
}

const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

/** A person someone follows posted. */
export function userPostNotice(a: { postId: string; post: Data }): Notice {
  const author = String(a.post.authorName ?? "") || "Someone";
  const workout = a.post.kind === "workout";
  const preview = postPreview(a.post);
  return {
    category: "posts",
    route: `/posts/${a.postId}`,
    collapseId: `posts_user_${String(a.post.authorId ?? "")}`,
    text: (_, count) => ({
      title: count > 1 ? `${author}: ${count} new posts` : `${author} ${workout ? "shared a workout" : "posted"}`,
      body: preview,
    }),
  };
}

/** A team or group someone follows posted. */
export function teamPostNotice(a: { teamId: string; teamName: string; post: Data }): Notice {
  const preview = postPreview(a.post);
  return {
    category: "posts",
    teamId: a.teamId,
    route: `/teams/${a.teamId}`,
    collapseId: `posts_team_${a.teamId}`,
    text: (_, count) => ({
      title: count > 1 ? `${a.teamName}: ${count} new posts` : `${a.teamName} posted`,
      body: preview,
    }),
  };
}

/**
 * followCounts changes for a follow doc write: +1 for the target's
 * followers and the follower's `following` on create, -1 on delete.
 */
export function followCountChanges(
  followerUid: string,
  key: string,
  before?: Data,
  after?: Data,
): { key: string; field: "followers" | "following"; by: number }[] {
  const by = !before && after ? 1 : before && !after ? -1 : 0;
  if (by === 0) return [];
  return [
    { key, field: "followers", by },
    { key: followKey.user(followerUid), field: "following", by },
  ];
}
