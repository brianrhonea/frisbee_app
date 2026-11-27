// Entry point: Firebase Admin with Application Default Credentials (no key
// files), or the emulators when FIRESTORE_EMULATOR_HOST /
// FIREBASE_AUTH_EMULATOR_HOST are set. See apps/api/.env.example; on Cloud
// Run the environment comes from apps/api/deploy/service.yaml.
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { FirestoreBrowseRepository } from "./browse/repository.js";
import { photoBuckets } from "./browse/visibility.js";
import { configureImageBuckets } from "./browse/model.js";
import { FirestoreRateLimiter } from "./limits/limiter.js";
import { FirestoreCalendarRepository } from "./calendar/repository.js";
import { FirestoreMeRepository } from "./me/repository.js";
import { FirestoreExportRepository } from "./export/repository.js";
import { buildApp, trustHops } from "./app.js";
import { parseCorsOrigins } from "./cors.js";
import { cloudLoggingOptions } from "./logging.js";
import { closeOnSignals } from "./shutdown.js";
import { getStorage } from "firebase-admin/storage";
import { FirestoreDocStore } from "./firestore_store.js";
import { FirestoreDraftQueries } from "./drafts/repository.js";
import { FirestoreDocQueries } from "./queries.js";
import { FirestorePublicRankingRepository } from "./rankings/public_repository.js";
import { FirestorePublicTournamentRepository } from "./tournaments/public_repository.js";
import { ffmpegHeicDecoder } from "./media/image.js";
import { FirebaseMediaStorage } from "./media/storage.js";
import { VisionImageChecker } from "./media/vision.js";
import { FirestoreTeamRepository } from "./teams/repository.js";
import { LocalCipher, type PersonalCipher } from "./personal/cipher.js";
import { KmsCipher } from "./personal/kms.js";
import { webRevalidator } from "./web/revalidate.js";
import { livekitFromEnv } from "./meetings/livekit.js";
import { jobVerifierFromEnv } from "./payments/jobs.js";
import { payoutHoldDaysFromEnv, platformFeeFromEnv } from "./payments/service.js";
import { stripeFromEnv } from "./payments/stripe.js";
import { setMergedClaims } from "./account/claims.js";
import { configurePhotoTrust, trustedPhotoUrl } from "./media/photo_url.js";
import { accountGateModeFromEnv, assertStartupEnvironment, StartupConfigError } from "./startup_env.js";

// Fails fast (INF-6) when deployed without FIREBASE_PROJECT_ID or with a
// Stripe key whose mode doesn't match the project; see startup_env.ts.
const projectId = (() => {
  try {
    return assertStartupEnvironment();
  } catch (e) {
    if (e instanceof StartupConfigError) {
      console.error(`Startup configuration error: ${e.message}`);
      process.exit(1);
    }
    throw e;
  }
})();
const firebase = initializeApp({ projectId });
const db = getFirestore(firebase);
const auth = getAuth(firebase);
const appCheck = getAppCheck(firebase);
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST);

// Proxies in front of the API: 1 on Cloud Run (its front end), 2 behind a
// Firebase Hosting rewrite, 0 when nothing is (local runs).
const trustProxyHops = Number(process.env.TRUST_PROXY_HOPS ?? 1);

let credentialChecked = false;

// Trimmed: a secret saved with a trailing newline must still match the
// website's copy (which Vercel stores without one).
const webServerKey = process.env.WEB_SERVER_KEY?.trim() || undefined;
/** The Storage buckets whose pictures profiles may show (this project's, either domain). */
const profilePhotoBuckets = [...new Set([process.env.STORAGE_BUCKET?.trim(), `${projectId}.firebasestorage.app`, `${projectId}.appspot.com`].filter((b): b is string => Boolean(b)))];
configurePhotoTrust(profilePhotoBuckets, process.env.FIREBASE_STORAGE_EMULATOR_HOST);
configureImageBuckets(profilePhotoBuckets);
const imageUrl = storageUrl(process.env.STORAGE_BUCKET || `${projectId}.firebasestorage.app`);

const app = buildApp({
  logger: cloudLoggingOptions(),
  enforceAppCheck: process.env.ENFORCE_APP_CHECK === "true",
  // The account gate: ACCOUNT_GATE_MODE enforce or report. Required when deployed; unset locally means report (startup_env.ts).
  accountGateMode: accountGateModeFromEnv(),
  // Cloud Scheduler's payment jobs (JOBS_AUDIENCE, JOBS_INVOKER).
  jobs: jobVerifierFromEnv(),
  corsOrigins: parseCorsOrigins(process.env.CORS_ORIGINS),
  trustProxy: trustProxyHops > 0 ? trustHops(trustProxyHops) : false,
  traceProjectId: projectId,
  // Ready once the service identity can get a Google access token: proves
  // the credentials work without a Firestore read on every probe.
  async ready() {
    if (credentialChecked || emulated) return;
    await firebase.options.credential?.getAccessToken();
    credentialChecked = true;
  },
  verifier: {
    async verifyIdToken(token) {
      const t = await auth.verifyIdToken(token);
      return {
        uid: t.uid,
        name: t.name as string | undefined,
        email: t.email,
        authTime: t.auth_time,
        emailVerified: t.email_verified === true,
        // The account gate's claims: set only by the API (account/gate.ts).
        ...(t.ageOk === true && { ageOk: true }),
        ...(typeof t.terms === "number" && { terms: t.terms }),
        ...(t.staff === true && { staff: true }),
      };
    },
    async verifyAppCheck(token) {
      await appCheck.verifyToken(token);
    },
  },
  users: {
    async lookup(uid) {
      try {
        const u = await auth.getUser(uid);
        // A client can set its own Auth photoURL to anything; only our bucket's or Google's is passed on (F5).
        return { name: u.displayName, email: u.email, photoUrl: trustedPhotoUrl(u.photoURL, uid, profilePhotoBuckets, process.env.FIREBASE_STORAGE_EMULATOR_HOST) ?? undefined, createdAt: u.metadata.creationTime ? new Date(u.metadata.creationTime).toISOString() : undefined };
      } catch {
        return null;
      }
    },
    async update(uid, changes) {
      await auth.updateUser(uid, {
        ...(changes.name !== undefined && { displayName: changes.name }),
        ...(changes.photoUrl !== undefined && { photoURL: changes.photoUrl }),
      });
    },
    async setClaims(uid, claims) {
      // Merged, so other claims (staff) stay; no write when nothing changes.
      await setMergedClaims(auth, uid, claims);
    },
    async ageOkOf(uids) {
      const ok = new Set<string>();
      // getUsers takes at most 100 identifiers a call.
      for (let i = 0; i < uids.length; i += 100) {
        const found = await auth.getUsers(uids.slice(i, i + 100).map((uid) => ({ uid })));
        for (const u of found.users) if (u.customClaims?.ageOk === true) ok.add(u.uid);
      }
      return ok;
    },
    async setDisabled(uid, disabled) {
      await auth.updateUser(uid, { disabled });
      if (disabled) await auth.revokeRefreshTokens(uid);
    },
  },
  teams: new FirestoreTeamRepository(db),
  me: { repo: new FirestoreMeRepository(db), imageUrl },
  exports: new FirestoreExportRepository(db),
  calendar: new FirestoreCalendarRepository(db),
  publicUrl: process.env.PUBLIC_API_URL || undefined,
  // The website's address: its cached public pages are expired on changes.
  revalidate:
    process.env.WEB_SITE_URL && webServerKey
      ? webRevalidator(process.env.WEB_SITE_URL, webServerKey)
      : undefined,
  browse: {
    repo: new FirestoreBrowseRepository(db),
    limiter: new FirestoreRateLimiter(db),
    imageUrl,
    webServerKey,
    photoBuckets: photoBuckets(projectId, process.env.STORAGE_BUCKET),
  },
  publicTournaments: new FirestorePublicTournamentRepository(db),
  publicRankings: new FirestorePublicRankingRepository(db),
  store: new FirestoreDocStore(db),
  draftQueries: new FirestoreDraftQueries(db),
  queries: new FirestoreDocQueries(db),
  // Uploads need the bucket named (STORAGE_BUCKET, e.g. <project>.firebasestorage.app).
  media: process.env.STORAGE_BUCKET
    ? new FirebaseMediaStorage(getStorage(firebase).bucket(process.env.STORAGE_BUCKET))
    : undefined,
  heic: ffmpegHeicDecoder(),
  // Photo checks (Cloud Vision SafeSearch); off with the emulators or SAFE_SEARCH=off.
  images: emulated || process.env.SAFE_SEARCH === "off" ? undefined : visionChecker(),
  personal: personalCipher(),
  livekit: livekitFromEnv(),
  payments: paymentsConfig(),
});

/** Vision with the API's own credentials (Application Default Credentials). */
function visionChecker() {
  const credential = firebase.options.credential;
  if (!credential) return undefined;
  return new VisionImageChecker(async () => (await credential.getAccessToken()).access_token, {
    quotaProject: process.env.GOOGLE_CLOUD_QUOTA_PROJECT || undefined,
  });
}

/**
 * Stripe (STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET) and where it sends
 * people back (PAYMENTS_RETURN_URL, else WEB_SITE_URL). Missing any:
 * online payments are off and hosts collect fees themselves.
 */
function paymentsConfig() {
  const gateway = stripeFromEnv();
  const returnUrl = (process.env.PAYMENTS_RETURN_URL || process.env.WEB_SITE_URL || "").trim().replace(/\/+$/, "");
  if (!gateway || !returnUrl) return undefined;
  return { gateway, fee: platformFeeFromEnv(), returnUrl, holdDays: payoutHoldDaysFromEnv() };
}

/**
 * Cloud KMS (PERSONAL_DETAILS_KMS_KEY), or with the emulators only a local
 * key (PERSONAL_DETAILS_LOCAL_KEY). Neither: /v1/me/personal is off.
 */
function personalCipher(): PersonalCipher | undefined {
  const kmsKey = process.env.PERSONAL_DETAILS_KMS_KEY;
  if (kmsKey) return new KmsCipher(kmsKey);
  const localKey = process.env.PERSONAL_DETAILS_LOCAL_KEY;
  if (localKey) {
    if (!emulated) throw new Error("PERSONAL_DETAILS_LOCAL_KEY is for the emulators only; set PERSONAL_DETAILS_KMS_KEY.");
    return new LocalCipher(localKey);
  }
  return undefined;
}

/**
 * Storage's REST URL for [path]: it applies storage.rules to an
 * unauthenticated read, so visitors only get photos the rules let them
 * see (public authors' post photos).
 */
function storageUrl(bucket: string) {
  const host = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
  const base = host ? `http://${host}` : "https://firebasestorage.googleapis.com";
  return (path: string) => `${base}/v0/b/${bucket}/o/${encodeURIComponent(path)}?alt=media`;
}

closeOnSignals(app);

const port = Number(process.env.PORT ?? 8787);
app.listen({ port, host: "0.0.0.0" }).then(
  () => app.log.info(`Stall 10 API on :${port} (project ${projectId})`),
  (err) => {
    app.log.error(err);
    process.exit(1);
  },
);
