// Abuse protection and server-side reads, exported as the `api` group:
//   firebase deploy --only functions:api
//
// The app still writes messages, posts, comments and follows straight to
// Firestore (firestore.rules checks their shape). These triggers count
// each user's writes; past a limit (model.ts) the extra write is deleted
// and the user is muted for a while in `limits/{uid}`, which the rules
// check before letting them write again.

import {
  DocumentReference,
  type DocumentSnapshot,
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

import {
  type Action,
  type Counter,
  count,
  isMuted,
  limits,
  muteMs,
  searchKey,
  searchKinds,
  searchLimit,
  type SearchKind,
} from "./model";
import { enforceAppCheck } from "../options";

/** Callables only answer the real app once App Check is enforced. */
const callable = { enforceAppCheck };

/**
 * Counts one [action] by [uid]. Over the limit it mutes them and returns
 * true. Runs in a transaction so bursts can't slip through.
 */
export async function overLimit(uid: string, action: Action): Promise<boolean> {
  const db = getFirestore();
  const ref = db.doc(`limits/${uid}`);
  const now = Date.now();
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const prev = snap.get(`counts.${action}`) as Counter | undefined;
    const { counter, over } = count(prev, now, limits[action]);
    const mute = over ? { mutedUntil: Timestamp.fromMillis(now + muteMs) } : {};
    if (snap.exists) {
      // update() reads "counts.message" as a field path.
      tx.update(ref, {
        [`counts.${action}`]: counter,
        ...mute,
        ...(over ? { mutes: FieldValue.increment(1) } : {}),
      });
    } else {
      tx.set(ref, { counts: { [action]: counter }, ...mute, ...(over ? { mutes: 1 } : {}) });
    }
    return over;
  });
}

/**
 * Counts a created document's write; over the limit, deletes it (when
 * [remove]) so floods never reach other people.
 */
async function guard(
  snap: DocumentSnapshot | undefined,
  action: Action,
  uid: unknown,
  remove = true,
): Promise<void> {
  if (!snap || typeof uid !== "string" || uid.length === 0) return;
  if (!(await overLimit(uid, action))) return;
  logger.warn("Rate limit hit; muting", { uid, action, path: snap.ref.path });
  if (remove) await snap.ref.delete().catch(() => undefined);
}

const authorOf = (snap: DocumentSnapshot | undefined) => snap?.get("authorId");

export const teamMessageFlood = onDocumentCreated("teams/{teamId}/chats/{roomId}/messages/{id}", (e) =>
  guard(e.data, "message", authorOf(e.data)),
);
export const directMessageFlood = onDocumentCreated("conversations/{convId}/messages/{id}", (e) =>
  guard(e.data, "message", authorOf(e.data)),
);
export const meetingMessageFlood = onDocumentCreated("teams/{teamId}/meetings/{meetingId}/messages/{id}", (e) =>
  guard(e.data, "message", authorOf(e.data)),
);
export const postFlood = onDocumentCreated("posts/{postId}", (e) => guard(e.data, "post", authorOf(e.data)));
export const commentFlood = onDocumentCreated("posts/{postId}/comments/{id}", (e) =>
  guard(e.data, "comment", authorOf(e.data)),
);
// A private profile's owner writes the approved follow, so count the
// follower (the path's user) either way.
export const followFlood = onDocumentCreated("users/{uid}/follows/{key}", (e) =>
  guard(e.data, "follow", e.params.uid),
);
export const joinRequestFlood = onDocumentCreated("teams/{teamId}/joinRequests/{uid}", (e) =>
  guard(e.data, "joinRequest", e.params.uid),
);
// Teams are only counted: deleting one needs the full cleanup the app
// does, so the mute stops the next one instead.
export const teamFlood = onDocumentCreated("teams/{teamId}", (e) => guard(e.data, "team", e.data?.get("ownerId"), false));

/** Firestore values as plain JSON; timestamps become `{__ts: millis}`. */
function plain(value: unknown): unknown {
  if (value instanceof Timestamp) return { __ts: value.toMillis() };
  if (value instanceof DocumentReference) return value.path;
  if (Array.isArray(value)) return value.map(plain);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
  }
  return value;
}

/**
 * Searches players, people (for messages) or teams by one keyword. Rate
 * limited per user, so profiles can't be scraped in bulk. The app filters
 * and sorts the results as before.
 */
export const search = onCall(callable, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to search.");
  const data = (req.data ?? {}) as { kind?: unknown; key?: unknown };
  const kind = data.kind as SearchKind;
  const key = searchKey(data.key);
  if (!searchKinds.includes(kind) || !key) {
    throw new HttpsError("invalid-argument", "Nothing to search for.");
  }
  const db = getFirestore();
  const limitsSnap = await db.doc(`limits/${uid}`).get();
  const muted = limitsSnap.get("mutedUntil") as Timestamp | undefined;
  if (isMuted(muted?.toMillis(), Date.now()) || (await overLimit(uid, "search"))) {
    throw new HttpsError("resource-exhausted", "Too many searches. Try again in a few minutes.");
  }
  const queries =
    kind === "teams"
      ? [db.collection("teamDirectory").where("keywords", "array-contains", key)]
      : kind === "people"
        ? [db.collection("profiles").where("keywords", "array-contains", key)]
        : [
            db.collection("profiles").where("keywords", "array-contains", key),
            db.collection("profiles").where("tags", "array-contains", key),
          ];
  const snaps = await Promise.all(queries.map((q) => q.limit(searchLimit).get()));
  const byId = new Map<string, unknown>();
  for (const s of snaps) for (const d of s.docs) byId.set(d.id, plain(d.data()));
  return { results: [...byId].map(([id, d]) => ({ id, data: d })) };
});

/**
 * Health check for the uptime alert (scripts/monitoring): one cheap read.
 * Answers 200 when Firestore answers, 503 when it doesn't.
 */
export const health = onRequest({ maxInstances: 2 }, async (_req, res) => {
  try {
    await getFirestore().doc("meta/health").get();
    res.set("Cache-Control", "no-store").status(200).send("ok");
  } catch (e) {
    logger.error("Health check failed", e);
    res.status(503).send("unavailable");
  }
});
