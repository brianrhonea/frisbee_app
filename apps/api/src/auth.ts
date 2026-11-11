import { appCheckHeader } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { ApiError } from "./errors.js";

/** The signed-in caller, from their Firebase ID token. */
export interface Caller {
  uid: string;
  name?: string;
  email?: string;
}

/** Checks tokens; the Firebase Admin SDK in production, a fake in tests. */
export interface TokenVerifier {
  verifyIdToken(token: string): Promise<Caller>;
  /** Throws if the App Check token isn't valid. */
  verifyAppCheck(token: string): Promise<void>;
}

declare module "fastify" {
  interface FastifyRequest {
    caller: Caller | null;
  }
}

/** The name the app shows for [caller] (AppUser.label in the app). */
export function callerLabel(caller: Caller): string {
  return caller.name ? caller.name : (caller.email ?? "Player");
}

/**
 * Reads `Authorization: Bearer <ID token>` into `req.caller` (null when
 * absent) and checks the App Check header the way callables do: required
 * when [enforceAppCheck], otherwise checked only to log bad ones.
 */
export function registerAuth(app: FastifyInstance, verifier: TokenVerifier, enforceAppCheck: boolean) {
  app.decorateRequest("caller", null);
  app.addHook("onRequest", async (req) => {
    if (req.url === "/health") return;
    const appCheck = req.headers[appCheckHeader];
    if (typeof appCheck === "string" && appCheck) {
      try {
        await verifier.verifyAppCheck(appCheck);
      } catch (e) {
        if (enforceAppCheck) throw new ApiError("unauthenticated", "This app couldn't be verified. Update it and try again.");
        req.log.warn({ err: e }, "invalid App Check token");
      }
    } else if (enforceAppCheck) {
      throw new ApiError("unauthenticated", "This app couldn't be verified. Update it and try again.");
    }

    const header = req.headers.authorization;
    const match = header?.match(/^Bearer (.+)$/);
    if (!match) return;
    try {
      req.caller = await verifier.verifyIdToken(match[1]);
    } catch {
      throw new ApiError("unauthenticated", "Your session has expired. Sign in again.");
    }
  });
}

/** The caller, or a 401 for routes that need one. */
export function requireCaller(req: FastifyRequest): Caller {
  if (!req.caller) throw new ApiError("unauthenticated", "Not signed in.");
  return req.caller;
}
