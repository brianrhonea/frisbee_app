import { FieldValue, type Firestore } from "firebase-admin/firestore";
import type { Message, Messaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";

import {
  addItem,
  type Data,
  hasItem,
  type ItemKind,
  itemsWithout,
  itemText,
  type Notice,
  type Prefs,
  type Text,
  shouldPush,
  wants,
} from "./model";

// FIDs FCM no longer knows; their device docs are deleted.
const goneCodes = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/**
 * Sends [notice] to each of [uids] who wants it: one feed entry in
 * users/{uid}/notifications, plus a push to each of their devices.
 */
export async function deliver(
  db: Firestore,
  messaging: Messaging,
  uids: Iterable<string>,
  notice: Notice,
): Promise<void> {
  await Promise.all(
    [...new Set(uids)].map((uid) =>
      deliverTo(db, messaging, uid, notice).catch((e) =>
        logger.error("Notification failed", { uid, route: notice.route, error: String(e) }),
      ),
    ),
  );
}

async function deliverTo(db: Firestore, messaging: Messaging, uid: string, notice: Notice) {
  const user = db.collection("users").doc(uid);
  const prefs = ((await user.collection("settings").doc("notifications").get()).data() ?? {}) as Prefs;
  if (!wants(prefs, notice.category, notice.teamId, notice.roomId, notice.conversationId)) return;

  const feed = user.collection("notifications");
  const entry = notice.collapseId ? feed.doc(notice.collapseId) : feed.doc();
  const written = await db.runTransaction(async (tx) => {
    const previous = notice.collapseId ? await tx.get(entry) : undefined;
    // An undo that raced this trigger: the like, comment or request is gone.
    if (notice.check) {
      const source = await tx.get(db.doc(notice.check.path));
      const data = source.data();
      if (!data || (notice.check.holds && !notice.check.holds(data))) return null;
    }
    const before = previous?.exists ? previous.data() : undefined;
    const unread = before?.read === false;
    let count: number;
    let text: Text;
    let push: boolean;
    let items: unknown;
    if (notice.item && notice.itemKind) {
      // Folded by distinct item: the same liker or requester again isn't
      // one more, and doesn't buzz the phone again.
      const repeat = unread && hasItem(before?.items, notice.item.key);
      items = addItem(unread ? before?.items : [], notice.item);
      count = (items as unknown[]).length;
      text = itemText(notice.itemKind, items as never);
      push = !repeat && shouldPush(before, Date.now(), notice.pushId !== undefined);
    } else {
      // Repeats fold into the unread entry and count up; a read one starts over.
      // A repeat soon after the last push only updates the feed (shouldPush).
      count = unread ? Number(before?.count ?? 1) + 1 : 1;
      push = shouldPush(before, Date.now(), notice.pushId !== undefined);
      text = notice.text(prefs, count);
    }
    tx.set(entry, {
      category: notice.category,
      title: text.title,
      body: text.body,
      route: notice.route,
      teamId: notice.teamId ?? null,
      createdAt: FieldValue.serverTimestamp(),
      read: false,
      count,
      pushedAt: push ? FieldValue.serverTimestamp() : (before?.pushedAt ?? null),
      ...(notice.itemKind && { itemKind: notice.itemKind, items }),
      ...(notice.extra ?? {}),
    });
    return { text, push };
  });
  if (!written) return;
  const { text, push } = written;
  if (!push) return;

  const devices = await user.collection("devices").get();
  if (devices.empty) {
    // Feed only: they've never turned push on, or their phone couldn't
    // register (Notification settings on the phone says why).
    logger.info("No push devices", { uid, category: notice.category });
    return;
  }
  // Messages each get their own tag, so one doesn't replace the last on
  // Android; the app clears them all by the collapse id prefix.
  const tag = notice.pushId && notice.collapseId ? `${notice.collapseId}|${notice.pushId}` : notice.collapseId;
  const messages: Message[] = devices.docs.map((d) => ({
    fid: d.id,
    notification: { title: text.title, body: text.body },
    data: { route: notice.route, category: notice.category },
    android: {
      // Queued messages for a phone that was offline aren't dropped.
      collapseKey: notice.pushId ? undefined : notice.collapseId,
      notification: { tag },
    },
    apns: { payload: { aps: { sound: "default", threadId: notice.collapseId } } },
  }));
  const result = await messaging.sendEach(messages);
  logger.info("Push sent", {
    uid,
    category: notice.category,
    devices: devices.docs.map((d) => d.get("platform")),
    delivered: result.successCount,
    failed: result.failureCount,
  });
  await Promise.all(
    result.responses.map((r, i) => {
      if (!r.error) return undefined;
      if (goneCodes.has(r.error.code)) return devices.docs[i].ref.delete();
      // E.g. messaging/third-party-auth-error: the project has no APNs key.
      logger.warn("Push failed", {
        uid,
        platform: devices.docs[i].get("platform"),
        code: r.error.code,
        error: r.error.message,
      });
      return undefined;
    }),
  );
}

/**
 * Takes [key] back out of [uid]'s folded entry [entryId] (an unlike, a
 * deleted comment, a request taken back or answered, an undone repost or
 * follow): re-worded for what's left, or deleted when nothing is. Pushes
 * already sent stay sent.
 */
export async function retract(
  db: Firestore,
  uid: string,
  entryId: string,
  key: string,
  /**
   * Left alone if this doc exists again (and [holds] for it): triggers
   * aren't ordered, so an ask, take back, ask again must keep the request.
   */
  unless?: { path: string; holds?: (d: Data) => boolean },
): Promise<void> {
  const entry = db.doc(`users/${uid}/notifications/${entryId}`);
  try {
    await db.runTransaction(async (tx) => {
      if (unless) {
        const source = (await tx.get(db.doc(unless.path))).data();
        if (source && (!unless.holds || unless.holds(source))) return;
      }
      const snap = await tx.get(entry);
      const data = snap.data();
      if (!data || !Array.isArray(data.items)) return;
      const left = itemsWithout(data.items, key);
      if (left.length === data.items.length) return;
      if (left.length === 0) {
        tx.delete(entry);
        return;
      }
      const text = itemText(data.itemKind as ItemKind, left);
      tx.update(entry, { items: left, count: left.length, title: text.title, body: text.body });
    });
  } catch (e) {
    logger.error("Retract failed", { uid, entryId, error: String(e) });
  }
}

/** Deletes [uid]'s entry [entryId] if there is one (its post is gone). */
export async function removeEntry(db: Firestore, uid: string, entryId: string): Promise<void> {
  await db
    .doc(`users/${uid}/notifications/${entryId}`)
    .delete()
    .catch((e) => logger.error("Remove entry failed", { uid, entryId, error: String(e) }));
}
