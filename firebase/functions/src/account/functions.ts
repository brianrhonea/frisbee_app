// Account deletion, exported as the `account` group:
//   firebase deploy --only functions:account
// The app can't do this itself: the user's posts and messages are spread
// over teams and conversations whose rules don't let them be found or
// deleted from the client.

import { getAuth } from "firebase-admin/auth";
import { FieldPath, FieldValue, type Firestore, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  attachmentFolder,
  type Data,
  deletedUserName,
  eventResponsesOf,
  votedInPoll,
  nextOwner,
  postFolder,
  signedInRecently,
  signInFailure,
  signInHandle,
  wrongCredentials,
  type TeamMembers,
  tournamentWithout,
  userFolder,
} from "./model";
import { overLimit } from "../api/functions";
import { enforceAppCheck } from "../options";

// The project's web API key, for checking a password with Identity
// Toolkit (the Admin SDK can't). Set with
//   firebase functions:secrets:set WEB_API_KEY
const webApiKey = defineSecret("WEB_API_KEY");

/**
 * Signing in with a username: checks the password for the account that
 * owns [username], then returns its email so the app signs in with email
 * and password as usual. The email is only ever given to someone who
 * proved the password, and an unknown username fails exactly like a wrong
 * password, so this can't be used to look people up.
 */
export const signInEmail = onCall({ secrets: [webApiKey], enforceAppCheck }, async (req) => {
  const data = (req.data ?? {}) as { username?: unknown; password?: unknown };
  const handle = signInHandle(data.username);
  const password = typeof data.password === "string" ? data.password : "";
  const fail = (f = wrongCredentials) => new HttpsError(f.code, f.message);
  if (!handle || !password || password.length > 128) throw fail();
  // Unknown usernames count too, so this can't tell which ones exist.
  if (await overLimit(`signIn_${handle}`, "signIn")) {
    throw new HttpsError("resource-exhausted", "Too many tries. Wait 15 minutes and try again.");
  }

  const claim = await getFirestore().doc(`usernames/${handle}`).get();
  const uid = claim.get("uid");
  if (typeof uid !== "string") throw fail();
  let email: string | undefined;
  try {
    email = (await getAuth().getUser(uid)).email;
  } catch {
    throw fail();
  }
  if (!email) throw fail();

  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${webApiKey.value()}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: false }),
    },
  );
  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as { error?: { message?: string } };
    const failure = signInFailure(body.error?.message);
    if (failure.code === "unavailable") {
      logger.warn("Username sign-in check failed", { status: response.status, error: body.error?.message });
    }
    throw fail(failure);
  }
  return { email };
});

/**
 * Deletes the caller's account and everything they put in the app: their
 * posts, chat and direct messages (with attachments), event responses, chat poll votes,
 * join requests, profile (with its photos), personal details and private data. They leave every team; a team
 * they own passes to its next admin, or is deleted if nobody else is on
 * it. Messages other people sent them stay, under "Deleted user".
 *
 * The caller must have signed in again within the last few minutes.
 */
export const deleteAccount = onCall({ timeoutSeconds: 540, memory: "512MiB", enforceAppCheck }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to delete your account.");
  if (!signedInRecently(req.auth?.token.auth_time, Date.now())) {
    throw new HttpsError("failed-precondition", "Confirm it's you by signing in again, then delete your account.");
  }
  const db = getFirestore();
  logger.info("Deleting account", { uid });
  await deleteAccountFully(db, uid, realDeps);
  logger.info("Deleted account", { uid });
  return { deleted: true };
});

/** The two outside services the cascade uses, so tests can stand in for them. */
export interface DeleteDeps {
  /** Deletes every Storage file under [prefix]. */
  deleteFolder(prefix: string): Promise<void>;
  /** Deletes the login; an account that is already gone is fine. */
  deleteAuthUser(uid: string): Promise<void>;
}

export const realDeps: DeleteDeps = {
  deleteFolder: (prefix) => getStorage().bucket().deleteFiles({ prefix, force: true }),
  deleteAuthUser: async (uid) => {
    try {
      await getAuth().deleteUser(uid);
    } catch (e) {
      if ((e as { code?: string }).code !== "auth/user-not-found") throw e;
    }
  },
};

/**
 * The whole deletion: the data, then the login, then the age-refusal record.
 * That record goes last on purpose: for an under-13 account the scheduled
 * purge (account-purgeUnderThirteen) finds it by that record, so it stays
 * until nothing else is left to retry. Safe to run again at any point.
 */
export async function deleteAccountFully(db: Firestore, uid: string, deps: DeleteDeps): Promise<void> {
  await deleteUserData(db, uid, deps);
  await deps.deleteAuthUser(uid);
  // A refused under-18 birth date, kept sealed so a different one can't be tried (account gate F3).
  await db.doc(`ageRefusals/${uid}`).delete();
}

/** How long a disabled under-13 account is kept after its refusal (owner decision D-U13). */
export const under13RetentionMs = 30 * 24 * 3600_000;
/** Most accounts one scheduled run deletes; the rest wait for the next run. */
export const purgePerRun = 50;

export interface PurgeDeps extends DeleteDeps {
  /** The login's state: gone, disabled or enabled. */
  authState(uid: string): Promise<"missing" | "disabled" | "enabled">;
}

const realPurgeDeps: PurgeDeps = {
  ...realDeps,
  authState: async (uid) => {
    try {
      return (await getAuth().getUser(uid)).disabled ? "disabled" : "enabled";
    } catch (e) {
      if ((e as { code?: string }).code === "auth/user-not-found") return "missing";
      throw e;
    }
  },
};

export interface PurgeResult {
  /** Marked refusals at least 30 days old whose account was deleted this run. */
  deleted: number;
  /** Marked and old enough, but the login is enabled: left alone. */
  skippedEnabled: number;
  /** Ones that threw; the next run retries them. */
  failed: number;
}

/**
 * Deletes under-13 accounts, and all their data, 30 days after the refusal
 * (D-U13). The API marks such a refusal `under13: true` on ageRefusals/{uid};
 * only marked records whose `refusedAt` is at least 30 days old are acted on
 * (older records with no marker are never purged: an adult-only refusal
 * isn't one). The login must be disabled, or already gone from a run that
 * failed before it finished. It reuses the deleteAccount cascade, and the
 * marker goes last, so a failed run is retried by the next. Idempotent. Logs
 * uids and counts only.
 */
export async function purgeUnderThirteen(db: Firestore, now: number, deps: PurgeDeps = realPurgeDeps): Promise<PurgeResult> {
  const result: PurgeResult = { deleted: 0, skippedEnabled: 0, failed: 0 };
  const cutoff = now - under13RetentionMs;
  // Single-field equality, so no composite index; the age is checked below.
  let after: string | undefined;
  for (;;) {
    let q = db.collection("ageRefusals").where("under13", "==", true).orderBy(FieldPath.documentId()).limit(200);
    if (after) q = q.startAfter(after);
    const page = await q.get();
    for (const d of page.docs) {
      if (result.deleted + result.failed >= purgePerRun) break;
      const refusedAt = d.get("refusedAt");
      if (typeof refusedAt?.toMillis !== "function" || refusedAt.toMillis() > cutoff) continue;
      const uid = d.id;
      try {
        if ((await deps.authState(uid)) === "enabled") {
          result.skippedEnabled++;
          logger.warn("Under-13 refusal on an enabled account, not purged", { uid });
          continue;
        }
        await deleteAccountFully(db, uid, deps);
        result.deleted++;
      } catch (e) {
        result.failed++;
        logger.error("Under-13 purge failed for an account", { uid, error: String((e as { code?: string }).code ?? "error") });
      }
    }
    if (page.size < 200 || result.deleted + result.failed >= purgePerRun) break;
    after = page.docs[page.docs.length - 1]!.id;
  }
  logger.info("Under-13 purge", { ...result });
  return result;
}

/** Daily at 08:30 UTC. Deploying the account group creates its Cloud Scheduler job (and needs the Cloud Scheduler API on). */
export const purgeUnderThirteenDaily = onSchedule(
  { schedule: "30 8 * * *", timeZone: "Etc/UTC", timeoutSeconds: 540, memory: "512MiB", retryCount: 1 },
  async () => {
    const r = await purgeUnderThirteen(getFirestore(), Date.now());
    if (r.failed > 0) throw new Error(`Under-13 purge: ${r.failed} failed`);
  },
);

/**
 * Everything but the login and the age-refusal record (deleteAccountFully
 * does those last). Safe to run again if it fails part way.
 *
 * Kept on purpose, for accounting and moderation: the payment ledger
 * (tournaments/{t}/payments, charges, stripePayments, payerCharges,
 * paymentIssues) and `reports`.
 */
export async function deleteUserData(db: Firestore, uid: string, deps: Pick<DeleteDeps, "deleteFolder"> = realDeps): Promise<void> {
  // Content first, while team membership still says where things are.
  await deleteAuthored(db, uid, deps);
  await unlinkRosterSpots(db, uid);
  await leaveConversations(db, uid);
  await leaveTeams(db, uid, deps);
  await deleteJoinRequests(db, uid);
  await removeReactions(db, uid);
  await deleteFollowRequestsSent(db, uid);
  await anonymiseSignups(db, uid);
  // Before users/{uid}, whose calendarInvites say which calendars to tidy.
  await leaveCalendars(db, uid);
  // Blocks are kept for both people (apps/api/src/moderation): take the
  // other person's record of this account too.
  await removeBlocks(db, uid);
  await db.recursiveDelete(db.doc(`users/${uid}`));
  // Free their username for someone else.
  const names = await db.collection("usernames").where("uid", "==", uid).get();
  await Promise.all(names.docs.map((d) => d.ref.delete()));
  await db.recursiveDelete(db.doc(`profiles/${uid}`));
  // Encrypted personal details (apps/api/src/personal).
  await db.doc(`personalDetails/${uid}`).delete();
  // Rate-limit, export-time and suspension record, and the push-device owner map.
  await db.doc(`limits/${uid}`).delete();
  const devices = await db.collection("fidOwners").where("uid", "==", uid).get();
  await Promise.all(devices.docs.map((d) => d.ref.delete()));
  // Their follow counts (the followCount function skips a deleted profile, so nothing writes this back).
  await db.doc(`followCounts/user_${uid}`).delete();
  // Their profile and header photos, and any post photos left behind.
  await deps.deleteFolder(userFolder(uid));
}

/**
 * Their likes and reposts on other people's posts (posts/{id}.likedBy and
 * .repostedBy). The counts are those lists' lengths, so they follow. Their
 * own repost documents go with their posts. Collection-scope array-contains
 * queries, so no extra index. (Likes on comments need a collection-group
 * index and are not removed here.)
 */
async function removeReactions(db: Firestore, uid: string): Promise<void> {
  for (const field of ["likedBy", "repostedBy"] as const) {
    for (let round = 0; round < 1000; round++) {
      const snap = await db.collection("posts").where(field, "array-contains", uid).select().limit(500).get();
      if (snap.empty) break;
      const writer = db.bulkWriter();
      for (const d of snap.docs) void writer.update(d.ref, field, FieldValue.arrayRemove(uid));
      await writer.close();
    }
  }
}

/**
 * Requests they made to follow private profiles (profiles/{owner}/followRequests/{uid}).
 * Requests made to them go with profiles/{uid}. The request has no field
 * naming the requester, so look at each private profile, as deleteJoinRequests does.
 */
async function deleteFollowRequestsSent(db: Firestore, uid: string): Promise<void> {
  const owners = await db.collection("profiles").where("private", "==", true).select().get();
  const writer = db.bulkWriter();
  for (let i = 0; i < owners.docs.length; i += 300) {
    const refs = owners.docs.slice(i, i + 300).map((o) => o.ref.collection("followRequests").doc(uid));
    for (const r of await db.getAll(...refs)) if (r.exists) void writer.delete(r.ref);
  }
  await writer.close();
}

/**
 * Their sign-ups to tournaments (tournaments/{t}/signups/{uid}) keep the
 * division, status and skill so a host's lists and counts stay right, but
 * lose their name and gender. The ledger rows (tournaments/{t}/payments)
 * are kept for accounting. No field names the person, so each tournament is looked at.
 */
async function anonymiseSignups(db: Firestore, uid: string): Promise<void> {
  const tournaments = await db.collection("tournaments").select().get();
  const writer = db.bulkWriter();
  for (let i = 0; i < tournaments.docs.length; i += 300) {
    const refs = tournaments.docs.slice(i, i + 300).map((t) => t.ref.collection("signups").doc(uid));
    for (const r of await db.getAll(...refs)) {
      if (r.exists && r.get("name") !== deletedUserName) void writer.update(r.ref, { name: deletedUserName, gender: null });
    }
  }
  await writer.close();
}

/** The copies of [uid]'s blocks the other people hold (users/{other}/blocks/{uid}). */
async function removeBlocks(db: Firestore, uid: string): Promise<void> {
  const mine = await db.collection(`users/${uid}/blocks`).select().get();
  await Promise.all(mine.docs.map((d) => db.doc(`users/${d.id}/blocks/${uid}`).delete()));
}

/** Posts, comments and messages (team chats, meeting chats, direct messages). */
async function deleteAuthored(db: Firestore, uid: string, { deleteFolder }: Pick<DeleteDeps, "deleteFolder">): Promise<void> {
  const writer = db.bulkWriter();
  const posts = await db.collectionGroup("posts").where("authorId", "==", uid).get();
  for (const d of posts.docs) {
    const folder = postFolder(d.ref.path);
    if (folder) await deleteFolder(folder);
    void writer.delete(d.ref);
  }
  // Comments on anyone's posts (the posts' counts follow: follows-commentCount),
  // and notes, clips and comments on team videos (teams/{t}/videos/{v}/comments).
  const comments = await db.collectionGroup("comments").where("authorId", "==", uid).get();
  for (const d of comments.docs) void writer.delete(d.ref);
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

/**
 * Calendars (apps/api/src/calendar): theirs are deleted with their events
 * and outstanding invites ("My calendar"'s events go with users/{uid});
 * they're taken off everyone else's, invited or not; and their
 * subscription link stops working.
 */
/** Exported for test/server. */
export async function leaveCalendars(db: Firestore, uid: string): Promise<void> {
  const owned = await db.collection("calendars").where("ownerId", "==", uid).get();
  for (const d of owned.docs) {
    const pending = Object.keys((d.get("pending") ?? {}) as Record<string, unknown>);
    await Promise.all(pending.map((u) => db.doc(`users/${u}/calendarInvites/${d.id}`).delete()));
    await db.recursiveDelete(d.ref);
  }
  const writer = db.bulkWriter();
  const shared = await db.collection("calendars").where("memberIds", "array-contains", uid).get();
  for (const d of shared.docs) {
    if (d.get("ownerId") === uid) continue;
    void writer.update(d.ref, new FieldPath("members", uid), FieldValue.delete(), "memberIds", FieldValue.arrayRemove(uid));
  }
  const invites = await db.collection(`users/${uid}/calendarInvites`).get();
  for (const i of invites.docs) {
    const cal = db.doc(`calendars/${i.id}`);
    if ((await cal.get()).exists) void writer.update(cal, new FieldPath("pending", uid), FieldValue.delete());
  }
  await writer.close();
  const feed = await db.doc(`calendarFeedOwners/${uid}`).get();
  const hash = feed.get("hash");
  if (typeof hash === "string" && hash) await db.doc(`calendarFeeds/${hash}`).delete();
  await feed.ref.delete();
}

async function leaveTeams(db: Firestore, uid: string, deps: Pick<DeleteDeps, "deleteFolder">): Promise<void> {
  const teams = await db.collection("teams").where("memberIds", "array-contains", uid).get();
  for (const team of teams.docs) {
    const data = team.data() as TeamMembers & Data;
    const owner = data.ownerId === uid;
    const heir = owner ? nextOwner(data, uid) : undefined;
    if (owner && !heir) {
      await deleteTeam(db, team.id, deps);
      continue;
    }
    await scrubTeam(db, team.id, uid);
    const update: [FieldPath | string, unknown][] = [
      [new FieldPath("members", uid), FieldValue.delete()],
      [new FieldPath("memberNames", uid), FieldValue.delete()],
      ["memberIds", FieldValue.arrayRemove(uid)],
      ["statKeepers", FieldValue.arrayRemove(uid)],
      [new FieldPath("memberRoles", uid), FieldValue.delete()],
      [new FieldPath("memberPerms", uid), FieldValue.delete()],
      [new FieldPath("memberGrants", uid), FieldValue.delete()],
    ];
    if (Array.isArray(data.orgMembers)) update.push(["orgMembers", FieldValue.arrayRemove(uid)]);
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
    // Their answer and its note.
    const fields = eventResponsesOf(m.data(), uid);
    if (fields.length === 0) continue;
    const [first, ...rest] = fields.map((f) => [new FieldPath(f, uid), FieldValue.delete()] as const);
    void writer.update(m.ref, first[0], first[1], ...rest.flat());
  }

  // Their votes in chat polls (F33), room by room (poll.voterIds' automatic index).
  for (const room of (await ref.collection("chats").select().get()).docs) {
    const polls = await room.ref.collection("messages").where("poll.voterIds", "array-contains", uid).get();
    for (const m of polls.docs) {
      if (!votedInPoll(m.data(), uid)) continue;
      void writer.update(m.ref, new FieldPath("poll", "votes", uid), FieldValue.delete(), new FieldPath("poll", "voterIds"), FieldValue.arrayRemove(uid));
    }
  }

  const tournaments = await ref.collection("groupTournaments").where("participantIds", "array-contains", uid).get();
  for (const t of tournaments.docs) {
    const next = tournamentWithout(t.data(), uid);
    if (next) void writer.update(t.ref, next);
  }
  await writer.close();
}

/** A team nobody else is on: everything in it, its files and invite codes. */
async function deleteTeam(db: Firestore, teamId: string, { deleteFolder }: Pick<DeleteDeps, "deleteFolder">): Promise<void> {
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

/**
 * Requests to join groups (that approve who joins) and teams (that allow
 * join requests, F26) the user never got into. A team that turns requests
 * off declines those waiting (the API deletes them), so only these hold any.
 */
async function deleteJoinRequests(db: Firestore, uid: string): Promise<void> {
  const [groups, teams] = await Promise.all([
    db
      .collection("teams")
      .where("kind", "in", ["community", "organization"])
      .where("requiresApproval", "==", true)
      .select()
      .get(),
    db.collection("teams").where("allowJoinRequests", "==", true).select().get(),
  ]);
  if (groups.empty && teams.empty) return;
  const refs = [...groups.docs, ...teams.docs].map((g) => g.ref.collection("joinRequests").doc(uid));
  const writer = db.bulkWriter();
  for (let i = 0; i < refs.length; i += 300) {
    for (const r of await db.getAll(...refs.slice(i, i + 300))) {
      if (r.exists) void writer.delete(r.ref);
    }
  }
  await writer.close();
}
