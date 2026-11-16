import { FirebaseError } from "firebase/app";

/**
 * The person closed or cancelled the Google or Apple window (or opened a
 * second one): not a failure, so callers show nothing, as the app does
 * (isSignInCancelled in error_message.dart).
 */
const cancelCodes = new Set([
  "auth/popup-closed-by-user",
  "auth/cancelled-popup-request",
  "auth/user-cancelled",
  "auth/redirect-cancelled-by-user",
]);

export function isSignInCancelled(e: unknown): boolean {
  return e instanceof FirebaseError && cancelCodes.has(e.code);
}

/** The browser stopped the sign-in window from opening. */
export const popupBlockedMessage = "Your browser blocked the sign-in window. Allow pop-ups for this site and try again.";
