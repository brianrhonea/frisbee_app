import { FieldValue, type Firestore } from "firebase-admin/firestore";
import type { Message, Messaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";

import { type Notice, type Prefs, type Text, shouldPush, wants } from "./model";

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
  // A repeat soon after the last push only updates the feed (shouldPush).
  const { text, push } = await db.runTransaction(async (tx) => {
    const previous = notice.collapseId ? await tx.get(entry) : undefined;
    const before = previous?.exists ? previous.data() : undefined;
    const count = before?.read === false ? Number(before.count ?? 1) + 1 : 1;
    const push = shouldPush(before, Date.now());
    const text: Text = notice.text(prefs, count);
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
      ...(notice.extra ?? {}),
    });
    return { text, push };
  });
  if (!push) return;

  const devices = await user.collection("devices").get();
  if (devices.empty) {
    // Feed only: they've never turned push on, or their phone couldn't
    // register (Notification settings on the phone says why).
    logger.info("No push devices", { uid, category: notice.category });
    return;
  }
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
