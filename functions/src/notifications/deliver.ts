import { FieldValue, type Firestore } from "firebase-admin/firestore";
import type { Message, Messaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";

import { type Notice, type Prefs, type Text, wants } from "./model";

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
  if (!wants(prefs, notice.category, notice.teamId, notice.roomId)) return;

  const feed = user.collection("notifications");
  const entry = notice.collapseId ? feed.doc(notice.collapseId) : feed.doc();
  // Repeats fold into the unread entry and count up; a read one starts over.
  const text: Text = await db.runTransaction(async (tx) => {
    const previous = notice.collapseId ? await tx.get(entry) : undefined;
    const count =
      previous?.exists && previous.get("read") === false ? Number(previous.get("count") ?? 1) + 1 : 1;
    const text = notice.text(prefs, count);
    tx.set(entry, {
      category: notice.category,
      title: text.title,
      body: text.body,
      route: notice.route,
      teamId: notice.teamId ?? null,
      createdAt: FieldValue.serverTimestamp(),
      read: false,
      count,
    });
    return text;
  });

  const devices = await user.collection("devices").get();
  if (devices.empty) return;
  const messages: Message[] = devices.docs.map((d) => ({
    fid: d.id,
    notification: { title: text.title, body: text.body },
    data: { route: notice.route, category: notice.category },
    android: {
      collapseKey: notice.collapseId,
      notification: { tag: notice.collapseId },
    },
    apns: { payload: { aps: { sound: "default", threadId: notice.collapseId } } },
  }));
  const result = await messaging.sendEach(messages);
  await Promise.all(
    result.responses.map((r, i) =>
      r.error && goneCodes.has(r.error.code) ? devices.docs[i].ref.delete() : undefined,
    ),
  );
}
