"use client";
// Verify the email address (account gate, `email_unverified`): Firebase's own
// verification email, resend, and "I've verified", which reloads the user and
// gets a token that carries `email_verified` before anything is retried.
import { sendEmailVerification, signOut, type User } from "firebase/auth";
import { useState } from "react";
import { firebaseAuth } from "@/lib/firebase";

export const verifyEmailCopy = {
  title: "Verify your email",
  resent: "Email sent. Check your inbox and spam folder.",
  notYet: "We can't see that yet. Open the link in the email we sent, then try again.",
  resendFailed: "Couldn't send the email. Wait a moment and try again.",
  checkFailed: "Couldn't check. Check your connection and try again.",
} as const;

export function VerifyEmail({ user, onVerified }: { user: User; onVerified: () => void }) {
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");

  async function resend() {
    setBusy(true);
    setNotice("");
    setError("");
    try {
      await sendEmailVerification(user);
      setNotice(verifyEmailCopy.resent);
    } catch {
      setError(verifyEmailCopy.resendFailed);
    } finally {
      setBusy(false);
    }
  }

  async function verified() {
    setBusy(true);
    setNotice("");
    setError("");
    try {
      await user.reload();
      if (!user.emailVerified) {
        setError(verifyEmailCopy.notYet);
        return;
      }
      // email_verified comes from Auth, not the API: a fresh token carries it.
      await user.getIdToken(true);
      onVerified();
    } catch {
      setError(verifyEmailCopy.checkFailed);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="page">
      <div className="auth-card auth-card-wide" role="region" aria-label={verifyEmailCopy.title}>
        <header className="auth-head">
          <h1>{verifyEmailCopy.title}</h1>
          <p>
            We sent a link to <b>{user.email}</b>. Open it, then come back here and tap &ldquo;I&apos;ve verified&rdquo;.
          </p>
        </header>
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        {notice && (
          <p className="form-notice" role="status">
            {notice}
          </p>
        )}
        <button type="button" className="btn btn-primary" disabled={busy} onClick={() => void verified()}>
          I&apos;ve verified
        </button>
        <button type="button" className="btn" disabled={busy} onClick={() => void resend()}>
          Resend email
        </button>
        <button type="button" className="link-button small" disabled={busy} onClick={() => void signOut(firebaseAuth()!)}>
          Sign out
        </button>
      </div>
    </div>
  );
}
