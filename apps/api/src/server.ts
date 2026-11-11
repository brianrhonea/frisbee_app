// Entry point: Firebase Admin with Application Default Credentials (no key
// files), or the emulators when FIRESTORE_EMULATOR_HOST /
// FIREBASE_AUTH_EMULATOR_HOST are set. See apps/api/.env.example; on Cloud
// Run the environment comes from apps/api/deploy/service.yaml.
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { buildApp, trustHops } from "./app.js";
import { parseCorsOrigins } from "./cors.js";
import { cloudLoggingOptions } from "./logging.js";
import { closeOnSignals } from "./shutdown.js";
import { FirestoreTeamRepository } from "./teams/repository.js";

const projectId = process.env.FIREBASE_PROJECT_ID ?? "frisbee-app-brianrhonea-dev";
const firebase = initializeApp({ projectId });
const db = getFirestore(firebase);
const auth = getAuth(firebase);
const appCheck = getAppCheck(firebase);
const emulated = Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST);

// Proxies in front of the API: 1 on Cloud Run (its front end), 2 behind a
// Firebase Hosting rewrite, 0 when nothing is (local runs).
const trustProxyHops = Number(process.env.TRUST_PROXY_HOPS ?? 1);

let credentialChecked = false;

const app = buildApp({
  logger: cloudLoggingOptions(),
  enforceAppCheck: process.env.ENFORCE_APP_CHECK === "true",
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
});

closeOnSignals(app);

const port = Number(process.env.PORT ?? 8787);
app.listen({ port, host: "0.0.0.0" }).then(
  () => app.log.info(`Stall 10 API on :${port} (project ${projectId})`),
  (err) => {
    app.log.error(err);
    process.exit(1);
  },
);
