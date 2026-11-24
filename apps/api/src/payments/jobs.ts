// Scheduled payment jobs, called by Cloud Scheduler (DEPLOY.md,
// "Payments"): send hosts what's due, then check everything against
// Stripe. No Firebase ID token: Cloud Scheduler signs each call with a
// Google ID token (OIDC) for its own service account, and these routes
// accept only that account, with this API's URL as the audience. Without
// JOBS_AUDIENCE and JOBS_INVOKER both set, the routes answer 404.
import { paymentPaths, type ReconcileResult, type ReleaseResult } from "@stall10/shared";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { OAuth2Client } from "google-auth-library";
import { ApiError } from "../errors.js";

/** Checks the Google ID token on a job call; throws unless it's the scheduler's. */
export interface JobVerifier {
  verify(req: FastifyRequest): Promise<void>;
}

export interface PaymentJobs {
  releaseDue(): Promise<ReleaseResult>;
  reconcile(): Promise<ReconcileResult>;
}

const googleIssuers = new Set(["https://accounts.google.com", "accounts.google.com"]);

/** Google-signed tokens for [audience] from the service account [invoker] only. */
export function googleJobVerifier(audience: string, invoker: string, client = new OAuth2Client()): JobVerifier {
  const want = invoker.trim().toLowerCase();
  return {
    async verify(req) {
      const token = req.headers.authorization?.match(/^Bearer (.+)$/)?.[1];
      if (!token) throw new ApiError("unauthenticated", "Not signed in.");
      let payload;
      try {
        payload = (await client.verifyIdToken({ idToken: token, audience })).getPayload();
      } catch {
        throw new ApiError("unauthenticated", "Not signed in.");
      }
      if (!payload || !googleIssuers.has(payload.iss) || payload.email_verified !== true || payload.email?.toLowerCase() !== want) {
        throw new ApiError("permission_denied", "Only the scheduler can do that.");
      }
    },
  };
}

/** The job verifier from JOBS_AUDIENCE and JOBS_INVOKER, or none. */
export function jobVerifierFromEnv(env: NodeJS.ProcessEnv = process.env): JobVerifier | undefined {
  const audience = env.JOBS_AUDIENCE?.trim();
  const invoker = env.JOBS_INVOKER?.trim();
  return audience && invoker ? googleJobVerifier(audience, invoker) : undefined;
}

export function paymentJobRoutes(app: FastifyInstance, jobs: PaymentJobs, verifier: JobVerifier | undefined) {
  if (!verifier) return;
  // public: the Firebase sign-in hook leaves these to the check below.
  app.post(paymentPaths.jobRelease, { config: { public: true } }, async (req) => {
    await verifier.verify(req);
    const r = await jobs.releaseDue();
    req.log.info({ job: "payments-release", ...r }, "payment job");
    return r;
  });
  app.post(paymentPaths.jobReconcile, { config: { public: true } }, async (req) => {
    await verifier.verify(req);
    // Sends what's due first, so the check only flags what's really stuck.
    const sent = await jobs.releaseDue();
    const r = await jobs.reconcile();
    req.log.info({ job: "payments-reconcile", sent: sent.sent, ...r }, "payment job");
    if (r.issues > 0) req.log.warn({ job: "payments-reconcile", issues: r.issues }, "payment problems found");
    return r;
  });
}
