// Entry point: Firebase Admin with Application Default Credentials (no key
// files), or the emulators when FIRESTORE_EMULATOR_HOST /
// FIREBASE_AUTH_EMULATOR_HOST are set. See apps/api/.env.example.
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { buildApp } from "./app.js";
import { FirestoreBrowseRepository } from "./browse/repository.js";
import { FirestoreRateLimiter } from "./limits/limiter.js";
import { FirestoreTeamRepository } from "./teams/repository.js";

const projectId = process.env.FIREBASE_PROJECT_ID ?? "frisbee-app-brianrhonea-dev";
const firebase = initializeApp({ projectId });
const db = getFirestore(firebase);
const auth = getAuth(firebase);
const appCheck = getAppCheck(firebase);

const app = buildApp({
  logger: true,
  enforceAppCheck: process.env.ENFORCE_APP_CHECK === "true",
  verifier: {
    async verifyIdToken(token) {
      const t = await auth.verifyIdToken(token);
      return { uid: t.uid, name: t.name as string | undefined, email: t.email };
    },
    async verifyAppCheck(token) {
      await appCheck.verifyToken(token);
    },
  },
  users: {
    async lookup(uid) {
      try {
        const u = await auth.getUser(uid);
        return { name: u.displayName, email: u.email };
      } catch {
        return null;
      }
    },
  },
  teams: new FirestoreTeamRepository(db),
  browse: {
    repo: new FirestoreBrowseRepository(db),
    limiter: new FirestoreRateLimiter(db),
    imageUrl: storageUrl(process.env.FIREBASE_STORAGE_BUCKET ?? `${projectId}.firebasestorage.app`),
    webServerKey: process.env.WEB_SERVER_KEY || undefined,
  },
});

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

const port = Number(process.env.PORT ?? 8787);
app.listen({ port, host: "0.0.0.0" }).then(
  () => app.log.info(`Stall 10 API on :${port} (project ${projectId})`),
  (err) => {
    app.log.error(err);
    process.exit(1);
  },
);
