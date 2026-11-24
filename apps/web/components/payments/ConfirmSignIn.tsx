"use client";
// Setting up or changing payouts needs a sign-in in the last 15 minutes
// (payoutsReauthMessage, the API's 412). This asks the owner to confirm
// it's them in place: their password, or Google or Apple in a pop-up.
// The app does the same (PayoutsSetupScreen).
import { FirebaseError } from "firebase/app";
import {
  EmailAuthProvider,
  GoogleAuthProvider,
  OAuthProvider,
  reauthenticateWithCredential,
  reauthenticateWithPopup,
  type User,
} from "firebase/auth";
import { payoutsReauthMessage } from "@stall10/shared";
import { type FormEvent, useState } from "react";
import { isSignInCancelled, popupBlockedMessage } from "@/lib/auth_errors";

type Method = "password" | "google.com" | "apple.com";
const methodNames: Record<"google.com" | "apple.com", string> = { "google.com": "Google", "apple.com": "Apple" };

function methodOf(user: User): Method | null {
  const ids = user.providerData.map((p) => p.providerId);
  for (const m of ["password", "google.com", "apple.com"] as const) if (ids.includes(m)) return m;
  return null;
}

function problem(e: unknown): string {
  const code = e instanceof FirebaseError ? e.code : "";
  if (code === "auth/wrong-password" || code === "auth/invalid-credential") return "That password isn't right.";
  if (isSignInCancelled(e)) return "";
  if (code === "auth/popup-blocked") return popupBlockedMessage;
  if (code === "auth/too-many-requests") return "Too many tries. Wait a minute and try again.";
  if (code === "auth/user-mismatch") return "Use the account you're signed in with.";
  return "Couldn't confirm it's you. Try again.";
}

export function ConfirmSignIn({ user, onConfirmed }: { user: User; onConfirmed: () => void }) {
  const method = methodOf(user);
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function confirm(e?: FormEvent) {
    e?.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (method === "password") {
        await reauthenticateWithCredential(user, EmailAuthProvider.credential(user.email ?? "", password));
      } else if (method === "google.com") {
        await reauthenticateWithPopup(user, new GoogleAuthProvider());
      } else if (method === "apple.com") {
        await reauthenticateWithPopup(user, new OAuthProvider("apple.com"));
      }
      // A new ID token, so the API sees the new sign-in time.
      await user.getIdToken(true);
      onConfirmed();
    } catch (err) {
      setError(problem(err));
    } finally {
      setBusy(false);
    }
  }

  if (!method) {
    return <p className="form-error">For your security, sign out and sign in again, then set up or change payouts.</p>;
  }
  return (
    <form className="settings-form" onSubmit={(e) => void confirm(e)}>
      <p>{payoutsReauthMessage}</p>
      {method === "password" && (
        <label>
          Your password
          <input type="password" required value={password} autoComplete="current-password" onChange={(e) => setPassword(e.target.value)} />
        </label>
      )}
      <div className="form-actions">
        {error && (
          <span className="form-error" role="alert">
            {error}
          </span>
        )}
        <button className="btn btn-primary" type="submit" disabled={busy || (method === "password" && password === "")}>
          {busy ? "Checking…" : method === "password" ? "Confirm" : `Continue with ${methodNames[method]}`}
        </button>
      </div>
    </form>
  );
}
