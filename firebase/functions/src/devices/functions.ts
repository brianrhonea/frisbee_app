// Device-ownership trigger, exported as the `deviceOwnership` group so it
// can be deployed on its own:
//   firebase deploy --only functions:deviceOwnership

import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { claimFid, millisOf, releaseFid } from "./owners";

/** Keeps fidOwners/{fid} in step with users/{uid}/devices/{fid}. */
export const fidOwner = onDocumentWritten("users/{uid}/devices/{fid}", async (event) => {
  const { uid, fid } = event.params;
  const db = getFirestore();
  const after = event.data?.after;
  if (!after?.exists) {
    await releaseFid(db, uid, fid);
    return;
  }
  const at = millisOf(after.get("updatedAt"), Date.parse(event.time) || Date.now());
  const result = await claimFid(db, uid, fid, at);
  if (result === "takenOver" || result === "stale") logger.info("Device ownership", { fid, uid, result });
});
