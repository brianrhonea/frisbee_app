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
  "social",
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
  kind?: string;
  ownerId?: string;
  members?: Record<string, string>;
  memberIds?: string[];
  memberRoles?: Record<string, string[]>;
  memberPerms?: Record<string, string[]>;
  deletingAt?: unknown;
}

export interface RoomDoc {
  name?: string;
  readRoles?: string[];
  readUsers?: string[];
}

export type Data = Record<string, unknown>;

/**
 * Whether [prefs] allow [category], after the team override and the room or
 * conversation mute. A muted conversation is `dm/{id}` in mutedRooms
 * (NotificationPreferences.conversationKey in lib/domain/models).
 */
export function wants(
  prefs: Prefs | undefined,
  category: Category,
  teamId?: string,
  roomId?: string,
  conversationId?: string,
): boolean {
  if (teamId && roomId && prefs?.mutedRooms?.includes(`${teamId}/${roomId}`)) {
    return false;
  }
  if (conversationId && prefs?.mutedRooms?.includes(`dm/${conversationId}`)) {
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
    return role === "owner" || inAudience(team, uid, room.readRoles ?? [], room.readUsers ?? []);
  });
}

/** Whether [uid] is in an access list of ids (as firestore.rules' inAudience). */
function inAudience(team: TeamDoc, uid: string, ids: string[], users: string[] = []): boolean {
  const tier = team.members?.[uid] === "stats" ? "player" : team.members?.[uid];
  return (
    ids.includes("everyone") ||
    (tier !== undefined && ids.includes(tier)) ||
    (team.memberRoles?.[uid] ?? []).some((r) => ids.includes(r)) ||
    users.includes(uid)
  );
}

/**
 * Members who see a team event: everyone on a team or group; in a school
 * or club community, its audience and whoever manages events (as
 * firestore.rules' sees()).
 */
export function eventViewers(team: TeamDoc, event: Data | undefined): string[] {
  const ids = team.memberIds ?? [];
  if (team.kind !== "organization") return ids;
  const audience = Array.isArray(event?.audience) ? (event.audience as unknown[]).map(String) : [];
  return ids.filter((uid) => {
    const tier = team.members?.[uid];
    return (
      tier === "owner" ||
      tier === "coach" ||
      tier === "captain" ||
      (team.memberPerms?.[uid] ?? []).includes("manageEvents") ||
      inAudience(team, uid, audience)
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
/** How long repeats of an unread notification stay off the lock screen. */
export const quietRepeatMs = 10 * 60 * 1000;

/**
 * Whether a notice should buzz the phone, or only update the feed: a repeat
 * (same collapse id) of one still unread that already pushed in the last
 * [quietRepeatMs] stays quiet, so a busy chat is one push, not fifty.
 */
export function shouldPush(
  previous: { read?: unknown; pushedAt?: unknown } | undefined,
  nowMs: number,
  every = false,
): boolean {
  if (every || !previous || previous.read !== false) return true;
  const last = millis(previous.pushedAt);
  return last === undefined || nowMs - last >= quietRepeatMs;
}

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
  const all = (prefix: string) => files.every((f) => String((f as Data)?.contentType ?? "").startsWith(prefix));
  if (all("image/")) return files.length === 1 ? "📷 Photo" : `📷 ${files.length} photos`;
  if (all("video/")) return files.length === 1 ? "🎬 Video" : `🎬 ${files.length} videos`;
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
  /** A direct or group conversation, which its members can mute. */
  conversationId?: string;
  route: string;
  /**
   * Feed entry to fold repeats into (one per room or conversation); a new
   * entry each time when unset. Also groups the pushes on the device.
   */
  collapseId?: string;
  /** Worded per recipient: their time zone, and how many are unread. */
  text(prefs: Prefs, count: number): Text;
  /** More fields for the feed entry, e.g. followBack. */
  extra?: Data;
  /**
   * A message: every one buzzes the phone and gets its own lock-screen
   * entry (tagged `{collapseId}|{pushId}`), rather than folding quietly
   * into the last. The feed entry still folds.
   */
  pushId?: string;
  /**
   * Fold by distinct item (a liker, a comment, a request) instead of by
   * event: the entry keeps its items, counts them, and an undo takes one
   * back out (retract in deliver.ts). Worded by [itemText], not [text].
   */
  item?: NoticeItem;
  itemKind?: ItemKind;
  /**
   * Written only if this doc still exists (and [holds] for it) inside the
   * delivery transaction: an undo that raced the trigger isn't brought back.
   */
  check?: { path: string; holds?: (d: Data) => boolean };
}

/** One thing a folded entry counts: a liker, a comment, a follow request. */
export interface NoticeItem {
  key: string;
  name: string;
  body: string;
}

export type ItemKind = "likes" | "comments" | "replies" | "commentLikes" | "followRequests" | "repost" | "follower";

/** Most items one entry keeps (the count stops there too). */
export const maxItems = 50;

/** How a folded entry reads for its items, oldest first. */
export function itemText(kind: ItemKind, items: NoticeItem[]): Text {
  const n = items.length;
  const last = items[n - 1];
  const name = last?.name || "Someone";
  const body = last?.body ?? "";
  switch (kind) {
    case "likes":
      return { title: n > 1 ? `${n} new likes on your post` : `${name} liked your post`, body };
    case "comments":
      return { title: n > 1 ? `${n} new comments on your post` : `${name} commented on your post`, body };
    case "replies":
      return { title: n > 1 ? `${n} new replies to your comment` : `${name} replied to your comment`, body };
    case "commentLikes":
      return { title: n > 1 ? `${n} new likes on your comment` : `${name} liked your comment`, body };
    case "followRequests":
      return {
        title: n > 1 ? `${n} people want to follow you` : `${name} wants to follow you`,
        body: "Accept or decline in Settings.",
      };
    case "repost":
      return { title: `${name} reposted your post`, body };
    case "follower":
      return { title: `${name} started following you`, body: "" };
  }
}

function isItem(i: unknown): i is NoticeItem {
  return !!i && typeof i === "object" && typeof (i as NoticeItem).key === "string";
}

/** Stored items without [key]; an entry from before items has none. */
export function itemsWithout(raw: unknown, key: string): NoticeItem[] {
  return Array.isArray(raw) ? raw.filter((i): i is NoticeItem => isItem(i) && i.key !== key) : [];
}

/** [item] added to an entry's items (moved to the end if already there), newest last, capped. */
export function addItem(raw: unknown, item: NoticeItem): NoticeItem[] {
  return [...itemsWithout(raw, item.key), item].slice(-maxItems);
}

/** Whether the items already count [key] (a repeat: no new push). */
export function hasItem(raw: unknown, key: string): boolean {
  return Array.isArray(raw) && raw.some((i) => isItem(i) && i.key === key);
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

/**
 * A team chat message. Each one is pushed with its own text: no "3 new
 * messages" roll-up.
 */
export function chatNotice(a: {
  teamId: string;
  roomId: string;
  teamName: string;
  roomName: string;
  message: Data;
  messageId?: string;
}): Notice {
  const line = `${String(a.message.authorName ?? "Someone")}: ${messagePreview(a.message)}`;
  return {
    category: "chat",
    teamId: a.teamId,
    roomId: a.roomId,
    route: `/teams/${a.teamId}/chats/${a.roomId}`,
    collapseId: `chat_${a.teamId}_${a.roomId}`,
    pushId: a.messageId,
    text: () => ({ title: `${a.roomName} · ${a.teamName}`, body: line }),
  };
}

/** A direct or group message; each is pushed with its own text. */
export function directMessageNotice(a: {
  conversationId: string;
  message: Data;
  conversation?: Data;
  messageId?: string;
}): Notice {
  const preview = messagePreview(a.message);
  const author = String(a.message.authorName ?? "") || "Someone";
  // A group's notice is titled with the group, and says who wrote.
  const group = a.conversation?.kind === "group";
  const groupName = String(a.conversation?.name ?? "").trim() || "Group message";
  const line = group ? `${author}: ${preview}` : preview;
  return {
    category: "directMessages",
    conversationId: a.conversationId,
    route: `/messages/${a.conversationId}`,
    collapseId: `dm_${a.conversationId}`,
    pushId: a.messageId,
    text: () => ({
      title: group ? groupName : String(a.message.authorName ?? "New message"),
      body: line,
    }),
  };
}

/**
 * A message request: no preview, so reading the notification gives
 * nothing away. All requests fold into one entry.
 */
export function messageRequestNotice(a: { message: Data }): Notice {
  const name = String(a.message.authorName ?? "") || "Someone";
  return {
    category: "directMessages",
    route: "/messages",
    collapseId: "dmRequests",
    text: (_, count) => ({
      title: count > 1 ? `${count} new message requests` : "New message request",
      body: count > 1 ? "Open Messages, then Requests." : `${name} wants to send you a message.`,
    }),
  };
}

/**
 * Who hears about a direct message, and how: everyone in it but the
 * sender; whoever a request waits on as a request; nobody who declined it.
 */
export function directMessageRecipients(
  conversation: Data | undefined,
  senderId: string,
): { direct: string[]; requests: string[] } {
  const participants = ((conversation?.participants ?? []) as unknown[]).map(String);
  const status = String(conversation?.status ?? "accepted");
  const requestedOf = String(conversation?.requestedOf ?? "");
  const direct: string[] = [];
  const requests: string[] = [];
  for (const uid of participants) {
    if (uid === senderId) continue;
    if (uid === requestedOf && status === "request") requests.push(uid);
    else if (uid === requestedOf && status === "declined") continue;
    else direct.push(uid);
  }
  return { direct, requests };
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

/**
 * Someone asked to join a group that needs approval. Repeats fold into one
 * entry per group until it's read.
 */
export function joinRequestNotice(a: { teamId: string; teamName: string; request: Data }): Notice {
  const name = String(a.request.name ?? "") || "Someone";
  return {
    category: "teamActivity",
    teamId: a.teamId,
    route: `/teams/${a.teamId}/members`,
    collapseId: `joinRequest_${a.teamId}`,
    text: (_, count) => ({
      title: `${a.teamName}: request to join`,
      body: count > 1 ? `${count} people want to join · ${name}` : `${name} wants to join`,
    }),
  };
}

/** An owner or organizer invited the user to join their team or group. */
export function teamInviteNotice(a: { teamId: string; invite: Data }): Notice {
  const team = String(a.invite.teamName ?? "") || "a team";
  const from = String(a.invite.invitedByName ?? "") || "Someone";
  const kind = a.invite.kind === "community" ? "group" : "team";
  return {
    category: "teamActivity",
    teamId: a.teamId,
    route: "/teams",
    collapseId: `teamInvite_${a.teamId}`,
    text: () => ({
      title: `You're invited to join ${team}`,
      body: `${from} invited you to their ${kind}. Tap to accept or decline.`,
    }),
  };
}

/**
 * An invitation to someone's calendar (users/{uid}/calendarInvites/{id},
 * written by the API's CalendarService). Nothing is shared until they accept.
 */
export function calendarInviteNotice(a: { calendarId: string; invite: Data; fromName: string }): Notice {
  const calendar = String(a.invite.calendarName ?? "") || "a calendar";
  const from = a.fromName || "Someone";
  const can = a.invite.role === "edit" ? "see and add events" : "see its events";
  return {
    category: "social",
    route: "/settings/calendar",
    collapseId: `calendarInvite_${a.calendarId}`,
    text: () => ({
      title: `${from} shared a calendar with you`,
      body: `Accept to ${can} on "${calendar}".`,
    }),
  };
}

/** Team members a reminder goes to: everyone who hasn't said they can't go. */
export function reminderRecipients(team: TeamDoc, event: Data): string[] {
  const rsvps = (event.rsvps ?? {}) as Record<string, unknown>;
  return eventViewers(team, event).filter((uid) => rsvps[uid] !== "notGoing");
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
  if (post.kind === "repost") return "A repost";
  const event = post.kind === "event" ? (post.event as Data | undefined) : undefined;
  if (event) return clip(eventTitle(event), 120);
  const images = Array.isArray(post.images) ? post.images.length : 0;
  return images > 1 ? `📷 ${images} photos` : "📷 Photo";
}

const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

/** The original a repost points at (RepostOf in user_post.dart). */
export function repostOf(post: Data): { postId: string; authorId: string; authorName: string } | undefined {
  const r = post.kind === "repost" ? (post.repostOf as Data | undefined) : undefined;
  const postId = String(r?.postId ?? "");
  if (!r || !postId) return undefined;
  return { postId, authorId: String(r.authorId ?? ""), authorName: String(r.authorName ?? "") };
}

/** A person someone follows posted. */
export function userPostNotice(a: { postId: string; post: Data }): Notice {
  const author = String(a.post.authorName ?? "") || "Someone";
  const workout = a.post.kind === "workout";
  const reposted = repostOf(a.post);
  if (reposted) {
    const whose = reposted.authorName ? `${reposted.authorName}'s post` : "a post";
    const note = String(a.post.body ?? "").trim().replace(/\s+/g, " ");
    return {
      category: "posts",
      route: `/posts/${a.postId}`,
      collapseId: `posts_user_${String(a.post.authorId ?? "")}`,
      text: (_, count) => ({
        title: count > 1 ? `${author}: ${count} new posts` : `${author} reposted ${whose}`,
        body: clip(note, 120),
      }),
    };
  }
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

/** People who liked [after] since [before], other than its author. */
export function newLikers(before: Data | undefined, after: Data | undefined): string[] {
  const had = new Set(likedBy(before));
  const authorId = String(after?.authorId ?? "");
  return [...new Set(likedBy(after))].filter((uid) => !had.has(uid) && uid !== authorId);
}

/** Who a post's or comment's likes come from. */
export function likedBy(d?: Data): string[] {
  return Array.isArray(d?.likedBy) ? (d.likedBy as unknown[]).map(String) : [];
}

/** Likers who took their like back between [before] and [after]. */
export function removedLikers(before: Data | undefined, after: Data | undefined): string[] {
  const now = new Set(likedBy(after));
  return [...new Set(likedBy(before))].filter((uid) => !now.has(uid));
}

/** Someone liked your post; likes on one post fold into one entry. */
export function likeNotice(a: { postId: string; post: Data; likerName: string; likerId?: string }): Notice {
  const name = a.likerName || "Someone";
  const likerId = a.likerId;
  return {
    category: "social",
    route: `/posts/${a.postId}`,
    collapseId: `likes_${a.postId}`,
    ...(likerId && {
      itemKind: "likes" as const,
      item: { key: likerId, name, body: postPreview(a.post) },
      check: { path: `posts/${a.postId}`, holds: (d: Data) => likedBy(d).includes(likerId) },
    }),
    text: (_, count) => ({
      title: count > 1 ? `${count} new likes on your post` : `${name} liked your post`,
      body: postPreview(a.post),
    }),
  };
}

/** +1 for a new comment, -1 for a deleted one, 0 for an edit. */
export function commentCountChange(existedBefore: boolean, existsAfter: boolean): number {
  return existsAfter === existedBefore ? 0 : existsAfter ? 1 : -1;
}

/** Someone commented on your post; comments on one post fold together. */
export function commentNotice(a: { postId: string; post: Data; comment: Data; commentId?: string }): Notice {
  const name = String(a.comment.authorName ?? "") || "Someone";
  const text = String(a.comment.body ?? "").trim().replace(/\s+/g, " ");
  return {
    category: "social",
    route: `/posts/${a.postId}`,
    collapseId: `comments_${a.postId}`,
    ...(a.commentId && {
      itemKind: "comments" as const,
      item: { key: a.commentId, name, body: clip(text, 120) },
      check: { path: `posts/${a.postId}/comments/${a.commentId}` },
    }),
    text: (_, count) => ({
      title: count > 1 ? `${count} new comments on your post` : `${name} commented on your post`,
      body: clip(text, 120),
    }),
  };
}

/** Someone replied to your comment; replies to one comment fold together. */
export function replyNotice(a: { postId: string; parentId: string; comment: Data; commentId?: string }): Notice {
  const name = String(a.comment.authorName ?? "") || "Someone";
  const text = String(a.comment.body ?? "").trim().replace(/\s+/g, " ");
  return {
    category: "social",
    route: `/posts/${a.postId}`,
    collapseId: `replies_${a.postId}_${a.parentId}`,
    ...(a.commentId && {
      itemKind: "replies" as const,
      item: { key: a.commentId, name, body: clip(text, 120) },
      check: { path: `posts/${a.postId}/comments/${a.commentId}` },
    }),
    text: (_, count) => ({
      title: count > 1 ? `${count} new replies to your comment` : `${name} replied to your comment`,
      body: clip(text, 120),
    }),
  };
}

/** Someone liked your comment; likes on one comment fold together. */
export function commentLikeNotice(a: {
  postId: string;
  commentId: string;
  comment: Data;
  likerName: string;
  likerId?: string;
}): Notice {
  const name = a.likerName || "Someone";
  const text = String(a.comment.body ?? "").trim().replace(/\s+/g, " ");
  const likerId = a.likerId;
  return {
    category: "social",
    route: `/posts/${a.postId}`,
    collapseId: `commentLikes_${a.postId}_${a.commentId}`,
    ...(likerId && {
      itemKind: "commentLikes" as const,
      item: { key: likerId, name, body: clip(text, 120) },
      check: { path: `posts/${a.postId}/comments/${a.commentId}`, holds: (d: Data) => likedBy(d).includes(likerId) },
    }),
    text: (_, count) => ({
      title: count > 1 ? `${count} new likes on your comment` : `${name} liked your comment`,
      body: clip(text, 120),
    }),
  };
}

/**
 * Who hears about a new comment: the post's author, and for a reply the
 * author of the comment it answers. Never the commenter, never twice.
 */
export function commentRecipients(a: { postAuthorId: string; commentAuthorId: string; parentAuthorId?: string }): {
  postAuthor: boolean;
  parentAuthor: boolean;
} {
  const commenter = a.commentAuthorId;
  const postAuthor = !!a.postAuthorId && a.postAuthorId !== commenter;
  const parent = a.parentAuthorId ?? "";
  return { postAuthor, parentAuthor: !!parent && parent !== commenter && parent !== a.postAuthorId };
}

/** Someone reposted your post, with their note. */
export function repostNotice(a: { repostId: string; repost: Data; original?: Data }): Notice {
  const name = String(a.repost.authorName ?? "") || "Someone";
  const note = String(a.repost.body ?? "").trim().replace(/\s+/g, " ");
  return {
    category: "social",
    route: `/posts/${a.repostId}`,
    // One entry per repost, so undoing it takes the entry back.
    collapseId: `repost_${a.repostId}`,
    itemKind: "repost",
    item: { key: a.repostId, name, body: note ? clip(note, 120) : a.original ? postPreview(a.original) : "" },
    check: { path: `posts/${a.repostId}` },
    text: () => ({
      title: `${name} reposted your post`,
      body: note ? clip(note, 120) : a.original ? postPreview(a.original) : "",
    }),
  };
}

/** Someone started following you, with a way to follow them back. */
export function followerNotice(a: {
  followerId: string;
  name: string;
  photoUrl?: string | null;
  /** The follow doc; unfollowing before the entry is written means none. */
  followPath?: string;
}): Notice {
  const name = a.name || "Someone";
  return {
    category: "social",
    route: `/players/${a.followerId}`,
    // One entry per follower: following, unfollowing and following again isn't two.
    collapseId: `follower_${a.followerId}`,
    itemKind: "follower",
    item: { key: a.followerId, name, body: "" },
    ...(a.followPath && { check: { path: a.followPath } }),
    text: () => ({ title: `${name} started following you`, body: "" }),
    extra: { followBack: { uid: a.followerId, name, photoUrl: a.photoUrl ?? null } },
  };
}

/** Someone asked to follow a private profile: its owner hears. */
export function followRequestNotice(a: { requesterId: string; name: string; ownerId?: string }): Notice {
  const name = a.name || "Someone";
  return {
    category: "social",
    route: "/settings/follow-requests",
    // Several waiting fold into one entry, counted by person; one taken
    // back, declined or accepted drops out (retract).
    collapseId: "followRequests",
    itemKind: "followRequests",
    item: { key: a.requesterId, name, body: "" },
    ...(a.ownerId && { check: { path: `profiles/${a.ownerId}/followRequests/${a.requesterId}` } }),
    text: (_, count) =>
      count > 1
        ? { title: `${count} people want to follow you`, body: "Accept or decline in Settings." }
        : { title: `${name} wants to follow you`, body: "Accept or decline in Settings." },
  };
}

/** A private profile's owner accepted a follow request: the asker hears. */
export function followAcceptedNotice(a: { ownerId: string; name: string }): Notice {
  const name = a.name || "Someone";
  return {
    category: "social",
    route: `/players/${a.ownerId}`,
    text: () => ({ title: `${name} accepted your follow request`, body: "" }),
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
