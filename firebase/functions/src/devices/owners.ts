// Which account a push device (Firebase Installation ID) belongs to.
//
// An app registers its FID under users/{uid}/devices/{fid}. When a phone
// switches accounts and the old account's sign-out couldn't delete its
// copy (offline), that copy would keep getting the old account's pushes on
// the new account's phone. fidOwners/{fid} = {uid, updatedAt} is a
// server-only map (no client rules: Firestore denies what no rule matches)
// kept by the deviceOwnership trigger; the latest registration owns the FID.

import { type Firestore, Timestamp } from "firebase-admin/firestore";

export const ownersCollection = "fidOwners";

/** Milliseconds of a Firestore Timestamp (or a number), else [fallback]. */
export function millisOf(v: unknown, fallback: number): number {
  if (v instanceof Timestamp) return v.toMillis();
  if (typeof v === "number" && Number.isFinite(v)) return v;
  return fallback;
}

export type ClaimResult = "claimed" | "unchanged" | "takenOver" | "stale";

/**
 * [uid] registered [fid] at [at] (ms). Last write wins by the device doc's
 * updatedAt: a different current owner loses its device doc, a newer owner
 * makes this event stale.
 */
export async function claimFid(db: Firestore, uid: string, fid: string, at: number): Promise<ClaimResult> {
  const owner = db.collection(ownersCollection).doc(fid);
  return db.runTransaction(async (tx) => {
    const current = await tx.get(owner);
    const data = current.data();
    const currentUid = typeof data?.uid === "string" ? data.uid : undefined;
    const currentAt = millisOf(data?.updatedAt, 0);
    const mapping = { uid, updatedAt: Timestamp.fromMillis(at) };

    if (!current.exists || currentUid === undefined) {
      tx.set(owner, mapping);
      return "claimed";
    }
    if (currentUid === uid) {
      if (at > currentAt) tx.set(owner, mapping);
      return "unchanged";
    }
    // Owned by someone else: only a newer registration takes it over.
    if (at <= currentAt) return "stale";
    const old = db.doc(`users/${currentUid}/devices/${fid}`);
    // The old owner may have registered again since the map was written
    // (its own event not processed yet): then this one is the stale one.
    const oldDoc = await tx.get(old);
    if (oldDoc.exists && millisOf(oldDoc.get("updatedAt"), 0) > at) return "stale";
    if (oldDoc.exists) tx.delete(old);
    tx.set(owner, mapping);
    return "takenOver";
  });
}

/**
 * [uid]'s device doc for [fid] is gone. The mapping goes only if it still
 * names [uid]: after a takeover the old owner's delete must not remove the
 * new owner's mapping.
 */
export async function releaseFid(db: Firestore, uid: string, fid: string): Promise<boolean> {
  const owner = db.collection(ownersCollection).doc(fid);
  return db.runTransaction(async (tx) => {
    const current = await tx.get(owner);
    if (!current.exists || current.get("uid") !== uid) return false;
    tx.delete(owner);
    return true;
  });
}

/**
 * Which of [fids] the map says belong to a different account than [uid]:
 * one batched read. A missing mapping (not backfilled yet) counts as
 * owned by [uid].
 */
export async function ownedByOthers(db: Firestore, uid: string, fids: string[]): Promise<Set<string>> {
  if (fids.length === 0) return new Set();
  const refs = fids.map((f) => db.collection(ownersCollection).doc(f));
  const snaps = await db.getAll(...refs);
  const other = new Set<string>();
  snaps.forEach((s) => {
    const owner = s.get("uid");
    if (s.exists && typeof owner === "string" && owner !== uid) other.add(s.id);
  });
  return other;
}
