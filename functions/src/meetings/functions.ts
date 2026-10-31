// Meeting calls on LiveKit, exported as the `meetings` group:
//   firebase deploy --only functions:meetings
// Needs the LIVEKIT_URL (wss://…), LIVEKIT_API_KEY and LIVEKIT_API_SECRET
// secrets: `firebase functions:secrets:set LIVEKIT_API_KEY` and so on.

import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { AccessToken, RoomServiceClient } from "livekit-server-sdk";

import {
  displayName,
  joinDecision,
  type JoinRequestDoc,
  joinMessages,
  type MeetingDoc,
  meetingChange,
  type MeetingTeam,
  roomName,
} from "./model";

const livekitUrl = defineSecret("LIVEKIT_URL");
const livekitKey = defineSecret("LIVEKIT_API_KEY");
const livekitSecret = defineSecret("LIVEKIT_API_SECRET");
const secrets = [livekitUrl, livekitKey, livekitSecret];

const validId = (v: unknown): v is string => typeof v === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(v);

/**
 * A token to join a meeting's call, after the same checks as the rules:
 * a member who can see the meeting, while it's live, and let in by an
 * admin when it needs approval. Participants are named by uid, with their
 * photo in the metadata.
 */
export const joinToken = onCall({ secrets }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to join meetings.");
  const { teamId, meetingId } = (req.data ?? {}) as Record<string, unknown>;
  if (!validId(teamId) || !validId(meetingId)) {
    throw new HttpsError("invalid-argument", "Unknown meeting.");
  }
  const db = getFirestore();
  const meetingRef = db.doc(`teams/${teamId}/meetings/${meetingId}`);
  const [team, meeting, request, profile] = await Promise.all([
    db.doc(`teams/${teamId}`).get(),
    meetingRef.get(),
    meetingRef.collection("requests").doc(uid).get(),
    db.doc(`profiles/${uid}`).get(),
  ]);
  const teamData = team.data() as MeetingTeam | undefined;
  const decision = joinDecision({
    team: teamData,
    meeting: meeting.data() as MeetingDoc | undefined,
    request: request.data() as JoinRequestDoc | undefined,
    uid,
  });
  if (decision !== "ok") {
    const code = decision === "notStarted" || decision === "needsApproval" ? "failed-precondition" : "permission-denied";
    throw new HttpsError(code, joinMessages[decision]);
  }
  const photoUrl = profile.get("photoUrl");
  const token = new AccessToken(livekitKey.value().trim(), livekitSecret.value().trim(), {
    identity: uid,
    name: displayName(teamData!, uid, profile.get("name")),
    metadata: JSON.stringify(typeof photoUrl === "string" ? { photoUrl } : {}),
    ttl: "6h",
  });
  token.addGrant({
    room: roomName(teamId, meetingId),
    roomJoin: true,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
    canUpdateOwnMetadata: false,
  });
  return { url: livekitUrl.value().trim(), token: await token.toJwt() };
});

/**
 * Closes the call when a meeting ends or is deleted, so nobody stays
 * connected (clients leave on their own, but this doesn't rely on them).
 */
export const closeRoom = onDocumentWritten({ document: "teams/{teamId}/meetings/{meetingId}", secrets }, async (event) => {
  const change = meetingChange(
    event.data?.before.data() as MeetingDoc | undefined,
    event.data?.after.data() as MeetingDoc | undefined,
  );
  if (change !== "ended" && change !== "cancelled") return;
  const host = livekitUrl.value().trim().replace(/^ws/, "http");
  const rooms = new RoomServiceClient(host, livekitKey.value().trim(), livekitSecret.value().trim());
  const name = roomName(event.params.teamId, event.params.meetingId);
  try {
    await rooms.deleteRoom(name);
  } catch (e) {
    // Nobody joined, so there's no room to close.
    logger.info("No call to close", { room: name, error: String(e) });
  }
});
