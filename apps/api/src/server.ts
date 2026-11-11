// Entry point: Firebase Admin with Application Default Credentials (no key
// files), or the emulators when FIRESTORE_EMULATOR_HOST /
// FIREBASE_AUTH_EMULATOR_HOST are set. See apps/api/.env.example.
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { buildApp } from "./app.js";
import { FirestoreDocStore } from "./firestore_store.js";
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
        return { name: u.displayName, email: u.email, photoUrl: u.photoURL };
      } catch {
        return null;
      }
    },
  },
  teams: new FirestoreTeamRepository(db),
  store: new FirestoreDocStore(db),
});

const port = Number(process.env.PORT ?? 8787);
app.listen({ port, host: "0.0.0.0" }).then(
  () => app.log.info(`Stall 10 API on :${port} (project ${projectId})`),
  (err) => {
    app.log.error(err);
    process.exit(1);
  },
);
