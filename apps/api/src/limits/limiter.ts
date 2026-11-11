import { FieldValue, type Firestore, Timestamp } from "firebase-admin/firestore";
import { type Counter, count, isMuted, type Limit, muteMs } from "./model.js";

/** Decides whether a caller (uid or hashed IP) may make one more request. */
export interface RateLimiter {
  /** Counts one request for [key]; true if it's allowed. */
  admit(key: string, limit: Limit): Promise<boolean>;
}

/**
 * Counts in `limits/{key}` exactly as the Cloud Functions' overLimit does,
 * so a mute from either one applies to both.
 */
export class FirestoreRateLimiter implements RateLimiter {
  constructor(
    private readonly db: Firestore,
    private readonly action = "browse",
    private readonly now: () => number = Date.now,
  ) {}

  async admit(key: string, limit: Limit): Promise<boolean> {
    const ref = this.db.doc(`limits/${key}`);
    const now = this.now();
    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const muted = snap.get("mutedUntil") as Timestamp | undefined;
      if (isMuted(muted?.toMillis(), now)) return false;
      const prev = snap.get(`counts.${this.action}`) as Counter | undefined;
      const { counter, over } = count(prev, now, limit);
      const mute = over ? { mutedUntil: Timestamp.fromMillis(now + muteMs) } : {};
      if (snap.exists) {
        tx.update(ref, {
          [`counts.${this.action}`]: counter,
          ...mute,
          ...(over ? { mutes: FieldValue.increment(1) } : {}),
        });
      } else {
        tx.set(ref, { counts: { [this.action]: counter }, ...mute, ...(over ? { mutes: 1 } : {}) });
      }
      return !over;
    });
  }
}
