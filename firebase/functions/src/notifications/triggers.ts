// Notification triggers, exported as the `notifications` group so they can
// be deployed on their own:
//   firebase deploy --only functions:notifications

import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
  onDocumentWritten,
  onDocumentWrittenWithAuthContext,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { invitees, type MeetingDoc, meetingChange, type MeetingTeam, startedRecipients } from "../meetings/model";
import { trustedProfilePhoto } from "../media/photo_url";
import { isLeagueGameEvent } from "../tournaments/model";
import { deliver, removeEntry, retract } from "./deliver";
import { draftDeliveries, signupDecisionNotice } from "./league";
import { can as teamCan } from "../tournaments/chat_members";
import {
  becameFinal,
  deadlineOf,
  entryDeadlineNotice,
  finalNotice,
  millisOf,
  missingFor,
  organizerDeadlineNotice,
  reminderDue,
  scheduleCameOut,
  scheduleNotice,
  tournamentInviteNotice,
} from "./tournament";
import {
  chatNotice,
  commentLikeNotice,
  commentNotice,
  commentRecipients,
  type Data,
  directMessageNotice,
  directMessageRecipients,
  messageRequestNotice,
  eventChange,
  eventChangeNotice,
  eventViewers,
  isQuietSeriesWrite,
  joinApprovedNotice,
  joinRequestNotice,
  joinRequestRecipients,
  teamInviteNotice,
  calendarInviteNotice,
  meetingCancelledNotice,
  meetingInviteNotice,
  meetingStartedNotice,
  millis,
  followKeys,
  followerNotice,
  followAcceptedNotice,
  followRequestNotice,
  likeNotice,
  likedBy,
  newLikers,
  removedLikers,
  playNotice,
  postRecipients,
  replyNotice,
  repostNotice,
  repostOf,
  calendarReminderRecipients,
  reminderNotice,
  reminderRecipients,
  type RoomDoc,
  mentionedReaders,
  mentionNotice,
  roomReaders,
  type TeamDoc,
  teamPostNotice,
  userPostNotice,
  videoCommentNotice,
  videoCommentRecipients,
} from "./model";

const hour = 60 * 60 * 1000;

/** The team, unless it's gone or being deleted (see markDeleting in the rules). */
async function liveTeam(teamId: string): Promise<TeamDoc | undefined> {
  const team = (await getFirestore().doc(`teams/${teamId}`).get()).data() as TeamDoc | undefined;
  return team && !team.deletingAt ? team : undefined;
}

const teamName = (team: TeamDoc) => team.name || "Your team";

/** A team chat message: everyone who can read the room, except its author. */
export const chatMessage = onDocumentCreated(
  "teams/{teamId}/chats/{roomId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    const { teamId, roomId } = event.params;
    const [team, room] = await Promise.all([
      liveTeam(teamId),
      getFirestore().doc(`teams/${teamId}/chats/${roomId}`).get(),
    ]);
    const roomData = room.data() as RoomDoc | undefined;
    if (!team || !roomData) return;
    const recipients = roomReaders(team, roomData).filter((uid) => uid !== message.authorId);
    const about = {
      teamId,
      roomId,
      teamName: teamName(team),
      roomName: roomData.name || "Chat",
      message,
      messageId: event.params.messageId,
    };
    // @mentioned readers get "X mentioned you" instead of the room's notice.
    const mentioned = mentionedReaders(team, recipients, message);
    const personal = new Set(mentioned.personal);
    const byMention = new Set(mentioned.all);
    await Promise.all([
      deliver(getFirestore(), getMessaging(), recipients.filter((uid) => !byMention.has(uid)), chatNotice(about)),
      deliver(getFirestore(), getMessaging(), mentioned.personal, mentionNotice({ ...about, personal: true })),
      deliver(
        getFirestore(),
        getMessaging(),
        mentioned.all.filter((uid) => !personal.has(uid)),
        mentionNotice({ ...about, personal: false }),
      ),
    ]);
  },
);

/** A direct message: the other participant. */
export const directMessage = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    const { conversationId } = event.params;
    const conversation = (await getFirestore().doc(`conversations/${conversationId}`).get()).data();
    const to = directMessageRecipients(conversation, String(message.authorId ?? ""));
    if (to.direct.length) {
      await deliver(
        getFirestore(),
        getMessaging(),
        to.direct,
        directMessageNotice({ conversationId, message, conversation, messageId: event.params.messageId }),
      );
    }
    if (to.requests.length) {
      await deliver(getFirestore(), getMessaging(), to.requests, messageRequestNotice({ message }));
    }
  },
);

/**
 * A team event added, changed (not RSVPs, reactions or votes) or deleted:
 * every member but whoever did it. Past events are left alone.
 */
export const teamEvent = onDocumentWrittenWithAuthContext(
  "teams/{teamId}/events/{eventId}",
  async (event) => {
    const before = event.data?.before.data() as Data | undefined;
    const after = event.data?.after.data() as Data | undefined;
    const change = eventChange(before, after);
    if (!change) return;
    // A league's games go on schedules in bulk; no notice for each.
    if (isLeagueGameEvent(after ?? before)) return;
    // Nor for each event of a repeating series: one per series or bulk edit.
    if (isQuietSeriesWrite(before, after)) return;
    const start = millis((after ?? before)?.startsAt);
    if (start === undefined || start < Date.now()) return;
    const { teamId, eventId } = event.params;
    const team = await liveTeam(teamId);
    if (!team) return;
    await deliver(
      getFirestore(),
      getMessaging(),
      eventViewers(team, after ?? before).filter((uid) => uid !== event.authId),
      eventChangeNotice({ change, teamId, eventId, teamName: teamName(team), before, after }),
    );
  },
);

/**
 * Team meetings: invitees hear when they're invited and when an upcoming
 * meeting is cancelled; invitees attending hear when it starts, unless
 * they're already in the room or its lobby.
 */
export const teamMeeting = onDocumentWrittenWithAuthContext(
  "teams/{teamId}/meetings/{meetingId}",
  async (event) => {
    const before = event.data?.before.data() as (MeetingDoc & Data) | undefined;
    const after = event.data?.after.data() as (MeetingDoc & Data) | undefined;
    const change = meetingChange(before, after);
    if (change === null || change === "ended") return;
    const { teamId, meetingId } = event.params;
    const team = await liveTeam(teamId);
    if (!team) return;
    const meetingTeam = team as MeetingTeam;
    const db = getFirestore();
    const args = { teamId, meetingId, teamName: teamName(team) };
    const notActor = (uid: string) => uid !== event.authId;
    const upcoming = (m: Data) => (millis(m.startsAt) ?? 0) > Date.now() - hour;

    switch (change) {
      case "created":
        if (!upcoming(after!)) return;
        await deliver(
          db,
          getMessaging(),
          invitees(meetingTeam, after!).filter(notActor),
          meetingInviteNotice({ ...args, meeting: after! }),
        );
        return;
      case "cancelled":
        if (before!.status !== "live" && !upcoming(before!)) return;
        await deliver(
          db,
          getMessaging(),
          invitees(meetingTeam, before!).filter(notActor),
          meetingCancelledNotice({ ...args, meeting: before! }),
        );
        return;
      case "started": {
        const waiting = await db
          .collection(`teams/${teamId}/meetings/${meetingId}/requests`)
          .where("status", "in", ["pending", "admitted"])
          .get();
        await deliver(
          db,
          getMessaging(),
          startedRecipients(meetingTeam, after!, waiting.docs.map((d) => d.id)),
          meetingStartedNotice({ ...args, meeting: after! }),
        );
        return;
      }
    }
  },
);

/** A play added or saved: every member but whoever saved it. */
export const teamPlay = onDocumentWrittenWithAuthContext(
  "teams/{teamId}/plays/{playId}",
  async (event) => {
    const play = event.data?.after.data() as Data | undefined;
    if (!play) return;
    const { teamId, playId } = event.params;
    const team = await liveTeam(teamId);
    if (!team) return;
    const actor = event.authId ?? play.updatedBy;
    await deliver(
      getFirestore(),
      getMessaging(),
      (team.memberIds ?? []).filter((uid) => uid !== actor),
      playNotice({
        created: !event.data?.before.exists,
        teamId,
        playId,
        teamName: teamName(team),
        play,
      }),
    );
  },
);

/** A comment on a team video (F5): the video's author (videoCommentRecipients). */
export const videoComment = onDocumentCreated(
  "teams/{teamId}/videos/{videoId}/comments/{commentId}",
  async (event) => {
    const comment = event.data?.data();
    if (!comment) return;
    const { teamId, videoId, commentId } = event.params;
    const [team, video] = await Promise.all([
      liveTeam(teamId),
      getFirestore().doc(`teams/${teamId}/videos/${videoId}`).get(),
    ]);
    const videoData = video.data();
    if (!team || !videoData) return;
    const recipients = videoCommentRecipients(team, videoData, comment);
    if (recipients.length === 0) return;
    await deliver(
      getFirestore(),
      getMessaging(),
      recipients,
      videoCommentNotice({ teamId, videoId, teamName: teamName(team), video: videoData, comment, commentId }),
    );
  },
);

/**
 * A request to join a group that needs approval, or a team that allows
 * requests (F26): the owner and the admins who answer them.
 */
export const groupJoinRequest = onDocumentCreated(
  "teams/{teamId}/joinRequests/{userId}",
  async (event) => {
    const request = event.data?.data();
    if (!request) return;
    const { teamId, userId } = event.params;
    const team = await liveTeam(teamId);
    if (!team) return;
    const recipients = joinRequestRecipients(team, userId);
    if (recipients.length === 0) return;
    await deliver(
      getFirestore(),
      getMessaging(),
      recipients,
      joinRequestNotice({ teamId, teamName: teamName(team), request }),
    );
  },
);

/**
 * A join request went (F26): if the asker is now a member it was approved
 * (approving adds them and clears it in one write), so tell them. Declined
 * or withdrawn requests leave them outside: no push.
 */
export const joinRequestApproved = onDocumentDeleted(
  "teams/{teamId}/joinRequests/{userId}",
  async (event) => {
    const { teamId, userId } = event.params;
    const team = await liveTeam(teamId);
    if (!team || !(team.memberIds ?? []).includes(userId)) return;
    await deliver(
      getFirestore(),
      getMessaging(),
      [userId],
      joinApprovedNotice({ teamId, teamName: teamName(team), group: team.kind === "community" || team.kind === "organization" }),
    );
  },
);

const eventName = async (tournamentId: string): Promise<string> =>
  String((await getFirestore().doc(`tournaments/${tournamentId}`).get()).get("name") ?? "");

/** A captains' draft started, the turn passed, or the teams are set. */
export const leagueDraft = onDocumentWritten("tournaments/{tournamentId}/drafts/{divisionId}", async (event) => {
  const after = event.data?.after.data();
  if (!after) return;
  const { tournamentId, divisionId } = event.params;
  const deliveries = draftDeliveries({
    tournamentId,
    divisionId,
    eventName: await eventName(tournamentId),
    before: event.data?.before.data(),
    after,
  });
  const db = getFirestore();
  const messaging = getMessaging();
  await Promise.all(deliveries.map((d) => deliver(db, messaging, d.uids, d.notice)));
});

/** The host accepted, waitlisted or declined a player's signup: that player. */
export const signupDecision = onDocumentUpdated("tournaments/{tournamentId}/signups/{userId}", async (event) => {
  const { tournamentId, userId } = event.params;
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (before?.status === after?.status) return;
  const notice = signupDecisionNotice({ tournamentId, eventName: await eventName(tournamentId), before, after });
  if (notice) await deliver(getFirestore(), getMessaging(), [userId], notice);
});

/** An invitation to join a team or group: the person invited. */
export const teamInvite = onDocumentWrittenWithAuthContext(
  "users/{userId}/teamInvites/{teamId}",
  async (event) => {
    const invite = event.data?.after.data() as Data | undefined;
    if (!invite) return;
    const { userId, teamId } = event.params;
    if (!(await liveTeam(teamId))) return;
    await deliver(getFirestore(), getMessaging(), [userId], teamInviteNotice({ teamId, invite }));
  },
);

/**
 * An invitation to a calendar: the person invited, once (changing a pending
 * invite's role rewrites it without another push).
 */
export const calendarInvite = onDocumentCreated("users/{userId}/calendarInvites/{calendarId}", async (event) => {
  const invite = event.data?.data() as Data | undefined;
  if (!invite) return;
  const { userId, calendarId } = event.params;
  const db = getFirestore();
  const [calendar, profile] = await Promise.all([
    db.doc(`calendars/${calendarId}`).get(),
    typeof invite.fromId === "string" && invite.fromId ? db.doc(`profiles/${invite.fromId}`).get() : null,
  ]);
  // Withdrawn (or the calendar deleted) before this ran.
  const pending = calendar.get("pending") as Record<string, unknown> | undefined;
  if (!pending?.[userId]) return;
  const fromName = String(profile?.get("name") ?? "") || (profile?.get("username") ? `@${profile.get("username")}` : "");
  await deliver(db, getMessaging(), [userId], calendarInviteNotice({ calendarId, invite, fromName }));
});

/**
 * Followers of [keys] who turned on notifications for them (the bell on a
 * follow), from every user's `follows` subcollection.
 */
async function notifyingFollowers(keys: string[]): Promise<string[]> {
  if (keys.length === 0) return [];
  const snap = await getFirestore()
    .collectionGroup("follows")
    .where("key", "in", keys.slice(0, 30))
    .where("notify", "==", true)
    .get();
  return snap.docs.map((d) => d.ref.parent.parent?.id).filter((uid): uid is string => !!uid);
}

/** A person's name and photo from their public profile (the photo only when trusted: 3a-F). Exported for test/server. */
export async function profileOf(uid: string): Promise<{ name: string; photoUrl?: string | null }> {
  const p = (await getFirestore().doc(`profiles/${uid}`).get()).data();
  return { name: String(p?.name ?? ""), photoUrl: trustedProfilePhoto(p?.photoUrl, uid) };
}

/**
 * A person's post: followers of them, or of the tournament it's tagged with.
 * A repost also tells the original's author (who isn't told twice).
 */
export const userPost = onDocumentCreated("posts/{postId}", async (event) => {
  const post = event.data?.data();
  if (!post) return;
  const { postId } = event.params;
  const authorId = String(post.authorId ?? "");
  const reposted = repostOf(post);
  const privateAuthor =
    post.private === true || (authorId !== "" && (await getFirestore().doc(`profiles/${authorId}`).get()).get("private") === true);
  const followers = await notifyingFollowers(followKeys({ authorId, post, privateAuthor }));
  await deliver(
    getFirestore(),
    getMessaging(),
    postRecipients(followers, authorId).filter((uid) => uid !== reposted?.authorId),
    userPostNotice({ postId, post }),
  );
  if (reposted && reposted.authorId && reposted.authorId !== authorId) {
    const original = (await getFirestore().doc(`posts/${reposted.postId}`).get()).data();
    await deliver(getFirestore(), getMessaging(), [reposted.authorId], repostNotice({ repostId: postId, repost: post, original }));
  }
});

/** Someone liked a post: its author hears, likes on one post folded together. */
export const postLiked = onDocumentUpdated("posts/{postId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after) return;
  const authorId = String(after.authorId ?? "");
  const { postId } = event.params;
  for (const uid of newLikers(before, after)) {
    const liker = await profileOf(uid);
    await deliver(
      getFirestore(),
      getMessaging(),
      [authorId],
      likeNotice({ postId, post: after, likerName: liker.name, likerId: uid }),
    );
  }
  for (const uid of removedLikers(before, after)) {
    await retract(getFirestore(), authorId, `likes_${postId}`, uid, {
      path: `posts/${postId}`,
      holds: (d) => likedBy(d).includes(uid),
    });
  }
});

/** Someone followed a person: they hear, with a way to follow back. */
export const newFollower = onDocumentCreated("users/{uid}/follows/{key}", async (event) => {
  const follow = event.data?.data();
  if (!follow || follow.type !== "user") return;
  const target = String(follow.targetId ?? "");
  const followerId = event.params.uid;
  if (!target || target === followerId) return;
  // Accepted by the target (a private profile): they chose this, so the
  // asker hears instead.
  if (follow.approved === true) {
    const owner = await profileOf(target);
    await deliver(getFirestore(), getMessaging(), [followerId], followAcceptedNotice({ ownerId: target, ...owner }));
    return;
  }
  const follower = await profileOf(followerId);
  await deliver(
    getFirestore(),
    getMessaging(),
    [target],
    followerNotice({ followerId, ...follower, followPath: `users/${followerId}/follows/${event.params.key}` }),
  );
});

/** An unfollow takes back the "started following you" entry. */
export const followRemoved = onDocumentDeleted("users/{uid}/follows/{key}", async (event) => {
  const follow = event.data?.data();
  if (!follow || follow.type !== "user") return;
  const target = String(follow.targetId ?? "");
  const followerId = event.params.uid;
  if (!target || target === followerId) return;
  await retract(getFirestore(), target, `follower_${followerId}`, followerId, {
    path: `users/${followerId}/follows/${event.params.key}`,
  });
});

/** Someone asked to follow a private profile. */
export const followRequest = onDocumentCreated(
  "profiles/{uid}/followRequests/{requesterId}",
  async (event) => {
    const request = event.data?.data();
    if (!request) return;
    await deliver(
      getFirestore(),
      getMessaging(),
      [event.params.uid],
      followRequestNotice({
        requesterId: event.params.requesterId,
        name: String(request.name ?? ""),
        ownerId: event.params.uid,
      }),
    );
  },
);

/** A request taken back, declined or accepted drops out of the owner's entry. */
export const followRequestRemoved = onDocumentDeleted("profiles/{uid}/followRequests/{requesterId}", async (event) => {
  const { uid, requesterId } = event.params;
  await retract(getFirestore(), uid, "followRequests", requesterId, {
    path: `profiles/${uid}/followRequests/${requesterId}`,
  });
});

/**
 * Someone commented on a post: its author hears, unless it's their own.
 * A reply also tells the author of the comment it answers.
 */
export const postCommented = onDocumentCreated("posts/{postId}/comments/{commentId}", async (event) => {
  const comment = event.data?.data();
  if (!comment) return;
  const { postId } = event.params;
  const db = getFirestore();
  const post = (await db.doc(`posts/${postId}`).get()).data();
  if (!post) return;
  const postAuthorId = String(post.authorId ?? "");
  const parentId = typeof comment.parentId === "string" ? comment.parentId : undefined;
  const parent = parentId ? (await db.doc(`posts/${postId}/comments/${parentId}`).get()).data() : undefined;
  const to = commentRecipients({
    postAuthorId,
    commentAuthorId: String(comment.authorId ?? ""),
    parentAuthorId: parent ? String(parent.authorId ?? "") : undefined,
  });
  const { commentId } = event.params;
  if (to.postAuthor) {
    await deliver(db, getMessaging(), [postAuthorId], commentNotice({ postId, post, comment, commentId }));
  }
  if (to.parentAuthor && parent && parentId) {
    await deliver(db, getMessaging(), [String(parent.authorId)], replyNotice({ postId, parentId, comment, commentId }));
  }
});

/**
 * A deleted comment comes out of the post author's comments entry and the
 * parent author's replies entry; its own likes entry goes.
 */
export const commentRemoved = onDocumentDeleted("posts/{postId}/comments/{commentId}", async (event) => {
  const comment = event.data?.data();
  if (!comment) return;
  const { postId, commentId } = event.params;
  const db = getFirestore();
  const post = (await db.doc(`posts/${postId}`).get()).data();
  if (post?.authorId) await retract(db, String(post.authorId), `comments_${postId}`, commentId);
  const parentId = typeof comment.parentId === "string" ? comment.parentId : undefined;
  if (parentId) {
    const parent = (await db.doc(`posts/${postId}/comments/${parentId}`).get()).data();
    if (parent?.authorId) await retract(db, String(parent.authorId), `replies_${postId}_${parentId}`, commentId);
  }
  if (comment.authorId) await removeEntry(db, String(comment.authorId), `commentLikes_${postId}_${commentId}`);
});

/** Someone liked a comment: its author hears, likes on one comment folded together. */
export const commentLiked = onDocumentUpdated("posts/{postId}/comments/{commentId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after) return;
  const authorId = String(after.authorId ?? "");
  const { postId, commentId } = event.params;
  for (const uid of newLikers(before, after)) {
    const liker = await profileOf(uid);
    await deliver(
      getFirestore(),
      getMessaging(),
      [authorId],
      commentLikeNotice({ postId, commentId, comment: after, likerName: liker.name, likerId: uid }),
    );
  }
  for (const uid of removedLikers(before, after)) {
    await retract(getFirestore(), authorId, `commentLikes_${postId}_${commentId}`, uid, {
      path: `posts/${postId}/comments/${commentId}`,
      holds: (d) => likedBy(d).includes(uid),
    });
  }
});

/**
 * A deleted post: an undone repost comes out of the original author's
 * feed; an original's like and comment entries go with it.
 */
export const postRemoved = onDocumentDeleted("posts/{postId}", async (event) => {
  const post = event.data?.data();
  if (!post) return;
  const { postId } = event.params;
  const db = getFirestore();
  const reposted = repostOf(post);
  if (reposted?.authorId) {
    // A repost's id is the same each time (r_<original>_<reposter>).
    await retract(db, reposted.authorId, `repost_${postId}`, postId, { path: `posts/${postId}` });
    return;
  }
  const authorId = String(post.authorId ?? "");
  if (!authorId) return;
  await Promise.all([removeEntry(db, authorId, `likes_${postId}`), removeEntry(db, authorId, `comments_${postId}`)]);
});

/**
 * A team or group post: followers of the team, or of the tournament it's
 * about. Members-only posts go only to followers who are members, and so
 * do public ones while the team's public page is off.
 */
export const teamPost = onDocumentCreated("teams/{teamId}/posts/{postId}", async (event) => {
  const post = event.data?.data();
  if (!post) return;
  const { teamId } = event.params;
  const team = await liveTeam(teamId);
  if (!team) return;
  const followers = await notifyingFollowers(followKeys({ teamId, post }));
  await deliver(
    getFirestore(),
    getMessaging(),
    postRecipients(
      followers,
      String(post.authorId ?? ""),
      post.public === true && team.publicPage !== false ? undefined : team.memberIds ?? [],
    ),
    teamPostNotice({ teamId, teamName: teamName(team), post }),
  );
});

/**
 * Hourly: reminds people of team and personal events starting 23–24 hours
 * from now, then prunes old feed entries and reminder records.
 */
export const eventReminders = onSchedule(
  { schedule: "0 * * * *", timeZone: "Etc/UTC", timeoutSeconds: 300, retryCount: 1 },
  async () => {
    const db = getFirestore();
    const now = Date.now();
    const due = await db
      .collectionGroup("events")
      .where("startsAt", ">", Timestamp.fromMillis(now + 23 * hour))
      .where("startsAt", "<=", Timestamp.fromMillis(now + 24 * hour))
      .get();
    for (const doc of due.docs) {
      await remind(doc.ref.path, doc.data()).catch((e) =>
        logger.error("Reminder failed", { path: doc.ref.path, error: String(e) }),
      );
    }
    await prune(now);
  },
);

async function remind(path: string, event: Data) {
  const db = getFirestore();
  // Once per event and start time, even if the job retries; moving the
  // event earns a fresh reminder.
  const key = `${path.replace(/\//g, "_")}_${millis(event.startsAt)}`;
  try {
    await db.collection("sentReminders").doc(key).create({ sentAt: Timestamp.now() });
  } catch (e) {
    if ((e as { code?: number }).code === 6) return; // ALREADY_EXISTS
    throw e;
  }
  const [root, ownerId, , eventId] = path.split("/");
  if (root === "users") {
    await deliver(db, getMessaging(), [ownerId], reminderNotice({ event, route: `/my-events/${eventId}` }));
    return;
  }
  if (root === "calendars") {
    // A shared calendar (ownerId is its id): everyone on it. Its events have
    // no page of their own, so the reminder opens the schedule.
    const calendar = (await db.doc(`calendars/${ownerId}`).get()).data();
    const to = calendarReminderRecipients(calendar);
    if (to.length === 0) return;
    await deliver(
      db,
      getMessaging(),
      to,
      reminderNotice({ event, route: "/schedule", teamName: String(calendar?.name ?? "") || undefined }),
    );
    return;
  }
  if (root !== "teams") return;
  const team = await liveTeam(ownerId);
  if (!team) return;
  await deliver(
    db,
    getMessaging(),
    reminderRecipients(team, event),
    reminderNotice({
      event,
      route: `/team-events/${ownerId}/${eventId}`,
      teamId: ownerId,
      teamName: teamName(team),
    }),
  );
}

/** Feed entries older than 60 days, reminder records older than 3. */
async function prune(now: number) {
  const db = getFirestore();
  for (const query of [
    db.collectionGroup("notifications").where("createdAt", "<", Timestamp.fromMillis(now - 60 * 24 * hour)),
    db.collection("sentReminders").where("sentAt", "<", Timestamp.fromMillis(now - 3 * 24 * hour)),
  ]) {
    const old = await query.limit(450).get();
    if (old.empty) continue;
    const batch = db.batch();
    for (const d of old.docs) batch.delete(d.ref);
    await batch.commit();
  }
}

// ---- Hosted tournaments: invites, deadlines, the schedule, finals --------

const strs = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);

/** A team's admins (teamAdmin() in the rules: manageTeam). */
const teamAdmins = (team: Data | undefined): string[] =>
  team ? strs(team.memberIds).filter((u) => teamCan(team, u, "manageTeam")) : [];

/** An entry's captains for the event and its team's admins. */
async function entryPeople(teamId: string, entry: Data | undefined): Promise<string[]> {
  const team = (await liveTeam(teamId)) as Data | null | undefined;
  if (!team) return [];
  const members = strs(team.memberIds);
  return [...new Set([...teamAdmins(team), ...strs(entry?.captainIds).filter((u) => members.includes(u))])];
}

/** A host invited a team (or invited it again): its admins, to respond. */
export const tournamentInvite = onDocumentWritten("tournaments/{tournamentId}/entries/{teamId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (after?.status !== "invited") return;
  if (before?.status === "invited" && millisOf(before.replyBy) === millisOf(after.replyBy)) return;
  const { tournamentId, teamId } = event.params;
  const t = (await getFirestore().doc(`tournaments/${tournamentId}`).get()).data();
  if (!t || t.status === "draft") return;
  const team = await liveTeam(teamId);
  if (!team) return;
  await deliver(
    getFirestore(),
    getMessaging(),
    teamAdmins(team as Data),
    tournamentInviteNotice({
      tournamentId,
      teamId,
      eventName: String(t.name ?? ""),
      teamName: teamName(team),
      replyBy: millisOf(after.replyBy),
    }),
  );
});

/** The schedule came out: every entered team's captains and admins. */
export const tournamentScheduled = onDocumentUpdated("tournaments/{tournamentId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!scheduleCameOut(before, after)) return;
  const { tournamentId } = event.params;
  const db = getFirestore();
  const entries = await db.collection(`tournaments/${tournamentId}/entries`).where("status", "==", "accepted").limit(200).get();
  const people = new Set<string>();
  for (const e of entries.docs) for (const u of await entryPeople(e.id, e.data())) people.add(u);
  if (people.size === 0) return;
  await deliver(db, getMessaging(), people, scheduleNotice({ tournamentId, eventName: String(after?.name ?? "") }));
});

/**
 * A game's final score (confirmed, or set by the host): both teams'
 * captains for the event. Running scores never push.
 */
export const tournamentFinal = onDocumentUpdated(
  "tournaments/{tournamentId}/divisions/{divisionId}/games/{gameId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after || !becameFinal(before, after)) return;
    const { tournamentId, divisionId, gameId } = event.params;
    const db = getFirestore();
    const [t, d] = await Promise.all([
      db.doc(`tournaments/${tournamentId}`).get(),
      db.doc(`tournaments/${tournamentId}/divisions/${divisionId}`).get(),
    ]);
    if (!t.exists || !d.exists) return;
    const teamA = String(after.teamA ?? "");
    const teamB = String(after.teamB ?? "");
    const captains = (d.get("captains") ?? {}) as Record<string, unknown>;
    const drafted = Array.isArray(d.get("teams")) ? (d.get("teams") as Data[]) : [];
    const nameOf = async (id: string) => {
      const mine = drafted.find((x) => x.id === id);
      if (mine?.name) return String(mine.name);
      const e = await db.doc(`tournaments/${tournamentId}/entries/${id}`).get();
      return String(e.get("teamName") ?? "Team");
    };
    const [nameA, nameB] = await Promise.all([nameOf(teamA), nameOf(teamB)]);
    const to = [...new Set([...strs(captains[teamA]), ...strs(captains[teamB])])];
    if (to.length === 0) return;
    await deliver(
      db,
      getMessaging(),
      to,
      finalNotice({ tournamentId, gameId, eventName: String(t.get("name") ?? ""), nameA, nameB, scoreA: Number(after.scoreA), scoreB: Number(after.scoreB) }),
    );
  },
);

/**
 * Hourly: reminds teams (their admins and captains) and players of a
 * roster or fee still missing, three days before the entry deadline and
 * once it has passed; the organizers hear once when it passes with entries
 * still missing something. Each reminder once (sentReminders, pruned by
 * eventReminders after three days).
 */
export const entryDeadlineReminders = onSchedule(
  { schedule: "15 * * * *", timeZone: "Etc/UTC", timeoutSeconds: 300, retryCount: 1 },
  async () => {
    const db = getFirestore();
    const now = Date.now();
    const open = await db.collection("tournaments").where("status", "in", ["registration", "seeding", "scheduled"]).limit(500).get();
    for (const doc of open.docs) {
      await remindEntries(doc.id, doc.data(), now).catch((e) =>
        logger.error("Entry reminders failed", { tournamentId: doc.id, error: String(e) }),
      );
    }
  },
);

/** Records that [key] was sent; false if it already was. */
async function firstTime(key: string): Promise<boolean> {
  try {
    await getFirestore().collection("sentReminders").doc(key).create({ sentAt: Timestamp.now() });
    return true;
  } catch (e) {
    if ((e as { code?: number }).code === 6) return false; // ALREADY_EXISTS
    throw e;
  }
}

async function remindEntries(tournamentId: string, t: Data, now: number) {
  const deadline = deadlineOf(t);
  const kind = reminderDue(deadline, now, undefined);
  if (!kind || deadline == null) return;
  const db = getFirestore();
  const messaging = getMessaging();
  const eventName = String(t.name ?? "");
  const divisions = await db.collection(`tournaments/${tournamentId}/divisions`).get();
  const minRoster = new Map(divisions.docs.map((d) => [d.id, typeof d.get("minRoster") === "number" ? Number(d.get("minRoster")) : 7]));
  const payments = new Map((await db.collection(`tournaments/${tournamentId}/payments`).get()).docs.map((p) => [p.id, p.data()]));
  const active = ["applied", "accepted", "waitlisted"];
  let missingTeams = 0;
  const entries = await db.collection(`tournaments/${tournamentId}/entries`).where("status", "in", active).get();
  for (const e of entries.docs) {
    const entry = e.data();
    const missing = missingFor({ t, entry, minRoster: minRoster.get(String(entry.divisionId ?? "")) ?? 7, payment: payments.get(e.id), player: false, teamId: e.id });
    if (missing.length === 0) continue;
    missingTeams++;
    if (!(await firstTime(`entry_${tournamentId}_${e.id}_${kind}_${deadline}`))) continue;
    await deliver(db, messaging, await entryPeople(e.id, entry), entryDeadlineNotice({ tournamentId, teamId: e.id, eventName, kind, missing, deadline }));
  }
  if (t.entryType === "players") {
    const signups = await db.collection(`tournaments/${tournamentId}/signups`).where("status", "in", active).get();
    for (const s of signups.docs) {
      const missing = missingFor({ t, entry: s.data(), minRoster: 0, payment: payments.get(s.id), player: true });
      if (missing.length === 0 || !(await firstTime(`signup_${tournamentId}_${s.id}_${kind}_${deadline}`))) continue;
      await deliver(db, messaging, [s.id], entryDeadlineNotice({ tournamentId, teamId: null, eventName, kind, missing, deadline }));
    }
  }
  if (kind === "passed" && missingTeams > 0 && (await firstTime(`entryhost_${tournamentId}_${deadline}`))) {
    const host = (await liveTeam(String(t.hostId ?? ""))) as Data | null | undefined;
    const organizers = host ? strs(host.memberIds).filter((u) => teamCan(host, u, "manageEvents")) : [];
    await deliver(db, messaging, organizers, organizerDeadlineNotice({ tournamentId, eventName, teams: missingTeams }));
  }
}
