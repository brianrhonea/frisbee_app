// Account deletion, exported as the `account` group:
//   firebase deploy --only functions:account
// The app can't do this itself: the user's posts and messages are spread
// over teams and conversations whose rules don't let them be found or
// deleted from the client.

import { getAuth } from "firebase-admin/auth";
import { FieldPath, FieldValue, type Firestore, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import {
  attachmentFolder,
  type Data,
  deletedUserName,
  eventResponsesOf,
  nextOwner,
  postFolder,
  signedInRecently,
  type TeamMembers,
  tournamentWithout,
} from "./model";

/**
 * Deletes the caller's account and everything they put in the app: their
 * posts, chat and direct messages (with attachments), event responses,
 * join requests, profile and private data. They leave every team; a team
 * they own passes to its next admin, or is deleted if nobody else is on
 * it. Messages other people sent them stay, under "Deleted user".
 *
 * The caller must have signed in again within the last few minutes.
 */
export const deleteAccount = onCall({ timeoutSeconds: 540, memory: "512MiB" }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to delete your account.");
  if (!signedInRecently(req.auth?.token.auth_time, Date.now())) {
    throw new HttpsError("failed-precondition", "Confirm it's you by signing in again, then delete your account.");
  }
  const db = getFirestore();
  logger.info("Deleting account", { uid });
  await deleteUserData(db, uid);
  try {
    await getAuth().deleteUser(uid);
  } catch (e) {
    if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
  }
  logger.info("Deleted account", { uid });
  return { deleted: true };
});

/** Everything but the login itself. Safe to run again if it fails part way. */
async function deleteUserData(db: Firestore, uid: string): Promise<void> {
  // Content first, while team membership still says where things are.
  await deleteAuthored(db, uid);
  await unlinkRosterSpots(db, uid);
  await leaveConversations(db, uid);
  await leaveTeams(db, uid);
  await deleteJoinRequests(db, uid);
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.doc(`profiles/${uid}`).delete();
}

const bucket = () => getStorage().bucket();

async function deleteFolder(prefix: string): Promise<void> {
  await bucket().deleteFiles({ prefix, force: true });
}

/** Posts and messages (team chats, meeting chats, direct messages). */
async function deleteAuthored(db: Firestore, uid: string): Promise<void> {
  const writer = db.bulkWriter();
  const posts = await db.collectionGroup("posts").where("authorId", "==", uid).get();
  for (const d of posts.docs) {
    const folder = postFolder(d.ref.path);
    if (folder) await deleteFolder(folder);
    void writer.delete(d.ref);
  }
  const messages = await db.collectionGroup("messages").where("authorId", "==", uid).get();
  const folders = new Set<string>();
  for (const d of messages.docs) {
    const folder = attachmentFolder(d.ref.path, uid);
    if (folder) folders.add(folder);
    void writer.delete(d.ref);
  }
  for (const f of folders) await deleteFolder(f);
  await writer.close();
}

/** Roster spots linked to the user, on any team, past or present. */
async function unlinkRosterSpots(db: Firestore, uid: string): Promise<void> {
  const spots = await db.collectionGroup("roster").where("userId", "==", uid).get();
  const writer = db.bulkWriter();
  for (const d of spots.docs) void writer.update(d.ref, { userId: null });
  await writer.close();
}

/** The other person keeps the conversation and their own messages. */
async function leaveConversations(db: Firestore, uid: string): Promise<void> {
  const convs = await db.collection("conversations").where("participants", "array-contains", uid).get();
  const writer = db.bulkWriter();
  for (const d of convs.docs) {
    const data = d.data();
    const update: [FieldPath | string, unknown][] = [
      [new FieldPath("names", uid), deletedUserName],
      [new FieldPath("readAt", uid), FieldValue.delete()],
    ];
    if (data.lastSenderId === uid) {
      update.push(["lastMessage", ""], ["lastSenderId", ""]);
    }
    const [first, ...rest] = update;
    void writer.update(d.ref, first[0], first[1], ...rest.flat());
  }
  await writer.close();
}

async function leaveTeams(db: Firestore, uid: string): Promise<void> {
  const teams = await db.collection("teams").where("memberIds", "array-contains", uid).get();
  for (const team of teams.docs) {
    const data = team.data() as TeamMembers & Data;
    const owner = data.ownerId === uid;
    const heir = owner ? nextOwner(data, uid) : undefined;
    if (owner && !heir) {
      await deleteTeam(db, team.id);
      continue;
    }
    await scrubTeam(db, team.id, uid);
    const update: [FieldPath | string, unknown][] = [
      [new FieldPath("members", uid), FieldValue.delete()],
      [new FieldPath("memberNames", uid), FieldValue.delete()],
      ["memberIds", FieldValue.arrayRemove(uid)],
      ["statKeepers", FieldValue.arrayRemove(uid)],
    ];
    if (heir) {
      update.push(["ownerId", heir], [new FieldPath("members", heir), "owner"]);
      logger.info("Handed team to next admin", { teamId: team.id, heir });
    }
    const [first, ...rest] = update;
    await team.ref.update(first[0], first[1], ...rest.flat());
  }
}

/** What a team still holds about `uid` beyond their posts and messages. */
async function scrubTeam(db: Firestore, teamId: string, uid: string): Promise<void> {
  const ref = db.doc(`teams/${teamId}`);
  const writer = db.bulkWriter();
  void writer.delete(ref.collection("joins").doc(uid));
  void writer.delete(ref.collection("joinRequests").doc(uid));

  for (const e of (await ref.collection("events").get()).docs) {
    const fields = eventResponsesOf(e.data(), uid);
    if (fields.length === 0) continue;
    const [first, ...rest] = fields.map((f) => [new FieldPath(f, uid), FieldValue.delete()] as const);
    void writer.update(e.ref, first[0], first[1], ...rest.flat());
  }

  for (const m of (await ref.collection("meetings").get()).docs) {
    void writer.delete(m.ref.collection("requests").doc(uid));
  }

  const tournaments = await ref.collection("groupTournaments").where("participantIds", "array-contains", uid).get();
  for (const t of tournaments.docs) {
    const next = tournamentWithout(t.data(), uid);
    if (next) void writer.update(t.ref, next);
  }
  await writer.close();
}

/** A team nobody else is on: everything in it, its files and invite codes. */
async function deleteTeam(db: Firestore, teamId: string): Promise<void> {
  const ref = db.doc(`teams/${teamId}`);
  // Tells the notification functions not to announce the cascade.
  await ref.update({ deletingAt: FieldValue.serverTimestamp() });
  await deleteFolder(`teams/${teamId}/`);
  const codes = await db.collection("inviteCodes").where("teamId", "==", teamId).get();
  const writer = db.bulkWriter();
  for (const c of codes.docs) void writer.delete(c.ref);
  void writer.delete(db.doc(`teamDirectory/${teamId}`));
  await writer.close();
  await db.recursiveDelete(ref);
  logger.info("Deleted team with no other members", { teamId });
}

/** Requests to join groups the user never got into. */
async function deleteJoinRequests(db: Firestore, uid: string): Promise<void> {
  const groups = await db
    .collection("teams")
    .where("kind", "==", "community")
    .where("requiresApproval", "==", true)
    .select()
    .get();
  if (groups.empty) return;
  const refs = groups.docs.map((g) => g.ref.collection("joinRequests").doc(uid));
  const writer = db.bulkWriter();
  for (let i = 0; i < refs.length; i += 300) {
    for (const r of await db.getAll(...refs.slice(i, i + 300))) {
      if (r.exists) void writer.delete(r.ref);
    }
  }
  await writer.close();
}
