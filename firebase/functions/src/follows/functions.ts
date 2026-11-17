// Follow bookkeeping, exported as the `follows` group:
//   firebase deploy --only functions:follows

import { FieldValue, getFirestore, type Query, type QueryDocumentSnapshot } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { onDocumentCreated, onDocumentDeleted, onDocumentWritten } from "firebase-functions/v2/firestore";

import { commentCountChange, type Data, followCountChanges, followKey } from "../notifications/model";
import { isPrivateProfile, privacyChange, stampFor } from "./privacy";

/** Keeps followCounts/{key} in step as people follow and unfollow. */
export const followCount = onDocumentWritten("users/{uid}/follows/{key}", async (event) => {
  const before = event.data?.before.data() as Data | undefined;
  const after = event.data?.after.data() as Data | undefined;
  const changes = followCountChanges(event.params.uid, event.params.key, before, after);
  if (changes.length === 0) return;
  const db = getFirestore();
  const batch = db.batch();
  for (const c of changes) {
    batch.set(db.doc(`followCounts/${c.key}`), { [c.field]: FieldValue.increment(c.by) }, { merge: true });
  }
  await batch.commit();
});

/**
 * Deletes every follow of [key] once the target is gone. followCount then
 * takes each one off the counts.
 */
async function dropFollowsOf(key: string) {
  const db = getFirestore();
  for (;;) {
    const snap = await db.collectionGroup("follows").where("key", "==", key).limit(450).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const d of snap.docs) batch.delete(d.ref);
    await batch.commit();
  }
}

/** A deleted account: nobody follows it any more. */
export const profileDeleted = onDocumentDeleted("profiles/{uid}", (event) =>
  dropFollowsOf(followKey.user(event.params.uid)),
);

/** A deleted team or group: nobody follows it any more. */
export const teamDeleted = onDocumentDeleted("teams/{teamId}", (event) =>
  dropFollowsOf(followKey.team(event.params.teamId)),
);

/** A deleted group tournament: nobody follows it any more. */
export const groupTournamentDeleted = onDocumentDeleted(
  "teams/{groupId}/groupTournaments/{tournamentId}",
  (event) => dropFollowsOf(`tournament_${event.params.groupId}_${event.params.tournamentId}`),
);

/**
 * A person's post deleted, by them or with their account: its photos and
 * comments go too (the app deletes photos itself when it can; this catches
 * the rest).
 */
export const userPostDeleted = onDocumentDeleted("posts/{postId}", async (event) => {
  const { postId } = event.params;
  const db = getFirestore();
  await db.recursiveDelete(db.collection(`posts/${postId}/comments`));
  const authorId = String(event.data?.data()?.authorId ?? "");
  if (!authorId) return;
  await getStorage()
    .bucket()
    .deleteFiles({ prefix: `users/${authorId}/posts/${postId}/` });
});

/** Firestore's NOT_FOUND, e.g. updating a post that was deleted. */
const notFound = (e: unknown) => (e as { code?: number | string }).code === 5 || (e as { code?: string }).code === "not-found";

/** Deletes the replies to comment [commentId] on post [postId]. */
async function deleteReplies(postId: string, commentId: string) {
  const db = getFirestore();
  for (;;) {
    const snap = await db.collection(`posts/${postId}/comments`).where("parentId", "==", commentId).limit(450).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const d of snap.docs) batch.delete(d.ref);
    await batch.commit();
  }
}

/**
 * Keeps a post's commentCount in step as comments are added and deleted.
 * Comments deleted along with their post have no post left to count on.
 */
export const commentCount = onDocumentWritten("posts/{postId}/comments/{commentId}", async (event) => {
  const by = commentCountChange(event.data?.before.exists ?? false, event.data?.after.exists ?? false);
  if (by === 0) return;
  // A top-level comment takes its replies with it; each reply deleted
  // runs this again and takes itself off the count.
  const gone = by < 0 ? event.data?.before.data() : undefined;
  if (gone && gone.parentId == null) await deleteReplies(event.params.postId, event.params.commentId);
  try {
    await getFirestore().doc(`posts/${event.params.postId}`).update({ commentCount: FieldValue.increment(by) });
  } catch (e) {
    if (!notFound(e)) throw e;
  }
});

/**
 * A new post's `private` flag, when its writer left it out (apps before
 * 0.0.29) or got it wrong: its author's profile's (S1). Until then the
 * rules treat a post without it as public.
 */
export const postPrivacy = onDocumentCreated("posts/{postId}", async (event) => {
  const post = event.data?.data() as Data | undefined;
  const authorId = post?.authorId;
  if (typeof authorId !== "string" || !authorId) return;
  const db = getFirestore();
  const profile = (await db.doc(`profiles/${authorId}`).get()).data();
  const stamp = stampFor(post, profile);
  if (stamp === null) return;
  try {
    await event.data!.ref.update({ private: stamp });
  } catch (e) {
    if (!notFound(e)) throw e;
  }
});

/**
 * A profile turned private or public: every post of theirs follows (450 a
 * batch). Turning private, the people already following them are its
 * accepted followers; their follows say so (`approved`), so their feeds
 * ask for this person's posts one at a time, as for any private profile.
 */
export const profilePrivacy = onDocumentWritten("profiles/{uid}", async (event) => {
  if (
    privacyChange(event.data?.before.data() as Data | undefined, event.data?.after.data() as Data | undefined) === null
  )
    return;
  const { uid } = event.params;
  const db = getFirestore();
  // Two quick toggles can run out of order: stamp what the profile says
  // now, not what this event says.
  const profile = (await db.doc(`profiles/${uid}`).get()).data();
  if (!profile) return;
  const now = isPrivateProfile(profile);
  await eachPage(db.collection("posts").where("authorId", "==", uid), (d) =>
    d.get("private") === now ? null : { private: now },
  );
  if (!now) return;
  await eachPage(db.collectionGroup("follows").where("key", "==", followKey.user(uid)), (d) =>
    d.get("approved") === true ? null : { approved: true },
  );
});

/** Updates each document [q] finds with what [change] gives it, 450 a batch. */
async function eachPage(q: Query, change: (d: QueryDocumentSnapshot) => Data | null) {
  const db = getFirestore();
  let after: QueryDocumentSnapshot | undefined;
  for (;;) {
    const snap = await (after ? q.startAfter(after) : q).limit(450).get();
    if (snap.empty) return;
    const batch = db.batch();
    let writes = 0;
    for (const d of snap.docs) {
      const update = change(d);
      if (update) {
        batch.update(d.ref, update);
        writes++;
      }
    }
    if (writes > 0) await batch.commit();
    if (snap.size < 450) return;
    after = snap.docs[snap.docs.length - 1];
  }
}
