"use client";
import { type FirebaseApp, getApps, initializeApp } from "firebase/app";
import { type Auth, connectAuthEmulator, getAuth } from "firebase/auth";

/**
 * Firebase on the website is for signing in only: every read and write of
 * app data goes through the API (ARCHITECTURE.md §6), except the live
 * reads the member area will add (chat, feeds, live stats).
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
};

export const authConfigured = Boolean(config.apiKey && config.projectId);

let app: FirebaseApp | undefined;
let auth: Auth | undefined;

/** Firebase Auth, or null when this deployment has no Firebase config. */
export function firebaseAuth(): Auth | null {
  if (!authConfigured) return null;
  if (!auth) {
    app = getApps()[0] ?? initializeApp(config);
    auth = getAuth(app);
    const emulator = process.env.NEXT_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST;
    if (emulator) connectAuthEmulator(auth, `http://${emulator}`, { disableWarnings: true });
  }
  return auth;
}
