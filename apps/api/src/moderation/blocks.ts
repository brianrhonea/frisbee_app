import { ApiError } from "../errors.js";
import type { Tx } from "../store.js";

/** Refused inside a transaction when [uid] and [other] blocked each other (the rules' blockedWith). */
export async function refuseBlocked(tx: Tx, uid: string, other: unknown): Promise<void> {
  if (typeof other !== "string" || !other || other === uid) return;
  if (await tx.get(`users/${uid}/blocks/${other}`)) {
    throw new ApiError("permission_denied", "You can't do that: one of you blocked the other.");
  }
}
