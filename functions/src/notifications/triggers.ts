// Notification triggers, exported as the `notifications` group so they can
// be deployed without the USA Ultimate functions:
//   firebase deploy --only functions:notifications

import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import {
  onDocumentCreated,
  onDocumentWrittenWithAuthContext,
} from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { deliver } from "./deliver";
import {
  chatNotice,
  type Data,
  directMessageNotice,
  eventChange,
  eventChangeNotice,
  millis,
  playNotice,
  reminderNotice,
  reminderRecipients,
  type RoomDoc,
  roomReaders,
  type TeamDoc,
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
    await deliver(
      getFirestore(),
      getMessaging(),
      recipients,
      chatNotice({ teamId, roomId, teamName: teamName(team), roomName: roomData.name || "Chat", message }),
    );
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
    const participants = (conversation?.participants ?? []) as string[];
    await deliver(
      getFirestore(),
      getMessaging(),
      participants.filter((uid) => uid !== message.authorId),
      directMessageNotice({ conversationId, message }),
    );
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
    const start = millis((after ?? before)?.startsAt);
    if (start === undefined || start < Date.now()) return;
    const { teamId, eventId } = event.params;
    const team = await liveTeam(teamId);
    if (!team) return;
    await deliver(
      getFirestore(),
      getMessaging(),
      (team.memberIds ?? []).filter((uid) => uid !== event.authId),
      eventChangeNotice({ change, teamId, eventId, teamName: teamName(team), before, after }),
    );
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
