// The real LiveKitSigner: livekit-server-sdk with LIVEKIT_URL (wss://…),
// LIVEKIT_API_KEY and LIVEKIT_API_SECRET, the same secrets the meetings
// callables use (firebase/functions/src/meetings/functions.ts). On Cloud
// Run they come from Secret Manager (apps/api/DEPLOY.md, "Meetings and
// voice"). Without all three, the token routes answer 412.
import { AccessToken } from "livekit-server-sdk";
import type { LiveKitSigner } from "./signer.js";

/** The signer, or undefined when any of the three isn't set. Values are trimmed, as the callables do. */
export function livekitFromEnv(env: NodeJS.ProcessEnv = process.env): LiveKitSigner | undefined {
  const url = env.LIVEKIT_URL?.trim();
  const key = env.LIVEKIT_API_KEY?.trim();
  const secret = env.LIVEKIT_API_SECRET?.trim();
  if (!url || !key || !secret) return undefined;
  return {
    url,
    async sign(req) {
      const token = new AccessToken(key, secret, { identity: req.identity, name: req.name, metadata: req.metadata, ttl: req.ttl });
      token.addGrant({
        room: req.room,
        roomJoin: true,
        canPublish: req.canPublish,
        canSubscribe: true,
        canPublishData: true,
        canUpdateOwnMetadata: false,
      });
      return token.toJwt();
    },
  };
}
