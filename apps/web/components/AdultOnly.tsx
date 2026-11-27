"use client";
// The dead end for anyone under 18 (adult-only launch; account-gate.md
// section 2): nothing to fix here, so no form and no retry, only the way out.
import { adultOnlyMessage } from "@stall10/shared";
import { signOut } from "firebase/auth";
import { useState } from "react";
import { deleteOwnAccount, firebaseAuth } from "@/lib/firebase";
import { ErrorNote } from "@/components/StatusViews";

export const adultOnlyCopy = {
  title: "Stall 10 is for players 18 and older",
  body: adultOnlyMessage,
  deletePrompt: "Delete your account and its data? This can't be undone.",
  deleteFailed: "Couldn't delete the account. Sign in again and retry, or email support@stall10.app.",
} as const;

export function AdultOnly() {
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function remove() {
    setBusy(true);
    setError("");
    try {
      // The full removal only: a login-only fallback would leave their data behind.
      await deleteOwnAccount({ loginOnlyFallback: false });
    } catch {
      setError(adultOnlyCopy.deleteFailed);
      setBusy(false);
    }
  }

  return (
    <div className="page">
      <div className="auth-card" role="alert">
        <h1>{adultOnlyCopy.title}</h1>
        <p>{adultOnlyCopy.body}</p>
        {error && <ErrorNote>{error}</ErrorNote>}
        {confirming ? (
          <>
            <p>{adultOnlyCopy.deletePrompt}</p>
            <button type="button" className="btn btn-primary" disabled={busy} onClick={() => void remove()}>
              {busy ? "Deleting…" : "Yes, delete my account"}
            </button>
            <button type="button" className="btn" disabled={busy} onClick={() => setConfirming(false)}>
              Cancel
            </button>
          </>
        ) : (
          <>
            <button type="button" className="btn btn-primary" onClick={() => void signOut(firebaseAuth()!)}>
              Sign out
            </button>
            <button type="button" className="btn" onClick={() => setConfirming(true)}>
              Delete account
            </button>
          </>
        )}
      </div>
    </div>
  );
}
