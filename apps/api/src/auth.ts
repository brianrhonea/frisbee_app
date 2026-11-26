import { type AccountGateField, accountGateFields, accountGateMessages, appCheckHeader, termsVersion } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { ApiError } from "./errors.js";

/** The signed-in caller, from their Firebase ID token. */
export interface Caller {
  uid: string;
  name?: string;
  email?: string;
  /** Stall 10 staff (the ID token's `staff` claim): reviews every report. */
  staff?: boolean;
  /** When the person last signed in (the ID token's auth_time, seconds). */
  authTime?: number;
  /** The ID token's `email_verified`. */
  emailVerified?: boolean;
  /** The `ageOk` claim: a saved birth date makes them 18 or over (set only by the API). */
  ageOk?: boolean;
  /** The `terms` claim: the Terms version they agreed to (set only by the API). */
  terms?: number;
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
  interface FastifyContextConfig {
    /**
     * Open to anyone, signed in or not (the website's public pages): no App
     * Check (browsers visiting the site have none), and a bad token is
     * treated as a visitor instead of an error.
     */
    public?: boolean;
    /**
     * "open": a write a new account may make before it is complete (the
     * account gate, docs/specifications/contracts/account-gate.md):
     * onboarding and own settings. Every other write by a signed-in caller
     * needs a verified email, the `ageOk` claim and the current `terms`.
     */
    accountGate?: "open";
  }
}

/**
 * The Auth user record's current name and email. ID tokens can lag behind
 * it by up to an hour (sign-up sets the name after creating the user, and
 * renames don't refresh the token), so names written to documents come
 * from here, not the token.
 */
export interface UserLookup {
  lookup(uid: string): Promise<{ name?: string; email?: string; photoUrl?: string; createdAt?: string } | null>;
  /** Changes the Auth record's name or photo (null removes it); absent where accounts can't be changed. */
  update?(uid: string, changes: { name?: string; photoUrl?: string | null }): Promise<void>;
  /**
   * Merges [claims] into the Auth user's custom claims (other claims, such
   * as `staff`, stay); absent where accounts can't be changed. The
   * account gate's `ageOk` and `terms` are only ever set here.
   */
  setClaims?(uid: string, claims: Record<string, unknown>): Promise<void>;
  /** Disables or enables sign-in (suspension), and signs a disabled account out. */
  setDisabled?(uid: string, disabled: boolean): Promise<void>;
}

/**
 * The name stored for [caller] on teams, invites and join requests: their
 * name, or "Player". Never their email, which teammates would see
 * (pentest P6; posts/author.ts does the same).
 */
export function callerLabel(caller: Caller): string {
  const name = caller.name?.trim();
  return name && !/\S@\S+\.\S/.test(name) ? name : "Player";
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
    const open = req.routeOptions.config?.public === true;
    const appCheck = req.headers[appCheckHeader];
    if (typeof appCheck === "string" && appCheck) {
      try {
        await verifier.verifyAppCheck(appCheck);
      } catch (e) {
        if (enforceAppCheck && !open) throw new ApiError("unauthenticated", "This app couldn't be verified. Update it and try again.");
        req.log.warn({ err: e }, "invalid App Check token");
      }
    } else if (enforceAppCheck && !open) {
      throw new ApiError("unauthenticated", "This app couldn't be verified. Update it and try again.");
    }

    const header = req.headers.authorization;
    const match = header?.match(/^Bearer (.+)$/);
    if (!match) return;
    try {
      req.caller = await verifier.verifyIdToken(match[1]);
    } catch {
      if (!open) throw new ApiError("unauthenticated", "Your session has expired. Sign in again.");
    }
    // The account gate: every write except the open ones. Before the body
    // is read, so nothing about an incomplete account's request is used.
    if (req.caller && !open && req.routeOptions.config?.accountGate !== "open" && !readMethods.has(req.method)) {
      requireCompleteAccount(req.caller);
    }
  });
}

const readMethods = new Set(["GET", "HEAD", "OPTIONS"]);

/** What [caller]'s token lacks of a complete account, in report order. */
export function accountGateMissing(caller: Caller): AccountGateField[] {
  const missing: AccountGateField[] = [];
  if (caller.emailVerified !== true) missing.push("email_unverified");
  if (caller.ageOk !== true) missing.push("age");
  if (typeof caller.terms !== "number" || caller.terms < termsVersion) missing.push("terms");
  return accountGateFields.filter((f) => missing.includes(f));
}

/** Throws account_incomplete (403) unless [caller] is a complete account. */
export function requireCompleteAccount(caller: Caller): void {
  const missing = accountGateMissing(caller);
  if (missing.length === 0) return;
  throw new ApiError(
    "account_incomplete",
    accountGateMessages[missing[0]!],
    Object.fromEntries(missing.map((f) => [f, accountGateMessages[f]])),
  );
}

/** The caller, or a 401 for routes that need one. */
export function requireCaller(req: FastifyRequest): Caller {
  if (!req.caller) throw new ApiError("unauthenticated", "Not signed in.");
  return req.caller;
}
