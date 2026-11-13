"use client";
import { type FirebaseApp, getApps, initializeApp } from "firebase/app";
import { type AppCheck, getToken, initializeAppCheck, ReCaptchaEnterpriseProvider } from "firebase/app-check";
import { type Auth, connectAuthEmulator, getAuth } from "firebase/auth";
import { connectFirestoreEmulator, type Firestore, getFirestore } from "firebase/firestore";
import { connectStorageEmulator, type FirebaseStorage, getStorage } from "firebase/storage";

/**
 * Firebase in the browser: signing in, App Check, reading stored photos the
 * member may see (Storage's rules decide), and the member area's reads from
 * Firestore (lib/live.ts), which the rules guard as they do for the app.
 * Every write goes through the API (lib/client.ts; ARCHITECTURE.md §4).
 *
 * Config comes from NEXT_PUBLIC_FIREBASE_* (apps/web/.env.local, or the
 * Vercel project's environment variables). The web API key ends up in the
 * page, which is normal for Firebase web apps; it still must never be
 * committed (CLAUDE.md).
 */
const config = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
};

export const authConfigured = Boolean(config.apiKey && config.projectId);

let app: FirebaseApp | undefined;
let auth: Auth | undefined;
let storage: FirebaseStorage | undefined;
let db: Firestore | undefined;
let appCheck: AppCheck | null | undefined;

function firebaseApp(): FirebaseApp {
  app ??= getApps()[0] ?? initializeApp(config);
  return app;
}

/** Firebase Auth, or null when this deployment has no Firebase config. */
export function firebaseAuth(): Auth | null {
  if (!authConfigured) return null;
  if (!auth) {
    auth = getAuth(firebaseApp());
    const emulator = process.env.NEXT_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST;
    if (emulator) connectAuthEmulator(auth, `http://${emulator}`, { disableWarnings: true });
  }
  return auth;
}

/** Cloud Storage, or null without config or a bucket. */
export function firebaseStorage(): FirebaseStorage | null {
  if (!authConfigured || !config.storageBucket) return null;
  if (!storage) {
    storage = getStorage(firebaseApp());
    const emulator = process.env.NEXT_PUBLIC_FIREBASE_STORAGE_EMULATOR_HOST;
    if (emulator) {
      const [host, port] = emulator.split(":");
      connectStorageEmulator(storage, host, Number(port));
    }
  }
  return storage;
}

/**
 * Firestore, or null without config. Starts App Check first when this site
 * has a site key, so reads carry its token if the project enforces it.
 */
export function firestoreDb(): Firestore | null {
  if (!authConfigured) return null;
  if (!db) {
    startAppCheck();
    db = getFirestore(firebaseApp());
    const emulator = process.env.NEXT_PUBLIC_FIRESTORE_EMULATOR_HOST;
    if (emulator) {
      const [host, port] = emulator.split(":");
      connectFirestoreEmulator(db, host, Number(port));
    }
  }
  return db;
}

function startAppCheck(): AppCheck | null {
  const siteKey = process.env.NEXT_PUBLIC_RECAPTCHA_SITE_KEY;
  if (!authConfigured || !siteKey) return null;
  appCheck ??= initializeAppCheck(firebaseApp(), {
    provider: new ReCaptchaEnterpriseProvider(siteKey),
    isTokenAutoRefreshEnabled: true,
  });
  return appCheck;
}

/**
 * An App Check token for API calls, when this deployment has a reCAPTCHA
 * Enterprise site key (NEXT_PUBLIC_RECAPTCHA_SITE_KEY). Without one the
 * API only accepts the call while ENFORCE_APP_CHECK is off.
 */
export async function appCheckToken(): Promise<string | null> {
  const check = startAppCheck();
  if (!check) return null;
  try {
    return (await getToken(check)).token;
  } catch {
    return null;
  }
}
