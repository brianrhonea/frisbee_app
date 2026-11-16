"use client";
// Settings → Account → Change password (the app's ChangePasswordDialog):
// the current password, which signs them in again as Firebase requires,
// then the new one twice, checked against the shared password policy.
import { passwordMaxLength, passwordProblem } from "@stall10/shared";
import { FirebaseError } from "firebase/app";
import { EmailAuthProvider, reauthenticateWithCredential, sendPasswordResetEmail, updatePassword, type User } from "firebase/auth";
import { type FormEvent, useState } from "react";
import { firebaseAuth } from "@/lib/firebase";
import { PasswordHints } from "../PasswordHints";

/** The app's errorMessage for the codes these calls give. */
function problem(e: unknown): string {
  switch (e instanceof FirebaseError ? e.code : "") {
    case "auth/invalid-credential":
    case "auth/wrong-password":
      return "Incorrect email or password.";
    case "auth/weak-password":
      return "That password is too weak. Use 8+ characters with a letter and a number.";
    case "auth/too-many-requests":
      return "Too many attempts. Wait a few minutes, or reset your password.";
    case "auth/requires-recent-login":
      return "Please sign out and sign in again, then retry.";
    case "auth/network-request-failed":
      return "Network unavailable. Check your connection.";
    default:
      return "Something went wrong.";
  }
}

/** What's wrong with the form, field by field, before Firebase sees it. */
function changePasswordProblems(current: string, next: string, confirm: string) {
  return {
    current: current ? null : "Enter your current password",
    next: passwordProblem(next) ?? (next === current ? "Pick a password different from your current one" : null),
    confirm: confirm === next ? null : "The passwords don't match",
  };
}

export function ChangePassword({ user }: { user: User }) {
  const [open, setOpen] = useState(false);
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [confirm, setConfirm] = useState("");
  const [checked, setChecked] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const problems = changePasswordProblems(current, next, confirm);

  function close() {
    setOpen(false);
    setCurrent("");
    setNext("");
    setConfirm("");
    setChecked(false);
    setError("");
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setChecked(true);
    setNotice("");
    if (problems.current || problems.next || problems.confirm) return;
    setBusy(true);
    setError("");
    try {
      await reauthenticateWithCredential(user, EmailAuthProvider.credential(user.email ?? "", current));
      await updatePassword(user, next);
      close();
      setNotice("Password changed");
    } catch (err) {
      setError(problem(err));
    } finally {
      setBusy(false);
    }
  }

  async function forgot() {
    const auth = firebaseAuth();
    if (!auth || !user.email) return;
    setError("");
    try {
      await sendPasswordResetEmail(auth, user.email);
      setNotice(`We sent a reset link to ${user.email}`);
    } catch (err) {
      setError(problem(err));
    }
  }

  const fieldError = (text: string | null) =>
    checked && text ? (
      <small className="form-error" role="alert">
        {text}
      </small>
    ) : null;

  return (
    <div className="card">
      <h2 className="card-title">Password</h2>
      {notice && (
        <p className="small" role="status">
          {notice}
        </p>
      )}
      {!open ? (
        <button className="btn" type="button" onClick={() => (setOpen(true), setNotice(""))}>
          Change password…
        </button>
      ) : (
        <form className="settings-form" onSubmit={(e) => void submit(e)} noValidate>
          <label>
            Current password
            <input type="password" value={current} autoComplete="current-password" onChange={(e) => setCurrent(e.target.value)} />
            {fieldError(problems.current)}
          </label>
          <div>
            <button className="btn btn-small" type="button" onClick={() => void forgot()}>
              Forgot it?
            </button>
          </div>
          <label>
            New password
            <input type="password" value={next} maxLength={passwordMaxLength} autoComplete="new-password" onChange={(e) => setNext(e.target.value)} />
            <PasswordHints password={next} />
            {fieldError(problems.next)}
          </label>
          <label>
            Confirm new password
            <input type="password" value={confirm} maxLength={passwordMaxLength} autoComplete="new-password" onChange={(e) => setConfirm(e.target.value)} />
            {fieldError(problems.confirm)}
          </label>
          <div className="form-actions">
            {error && (
              <span className="form-error" role="alert">
                {error}
              </span>
            )}
            <button className="btn" type="button" disabled={busy} onClick={close}>
              Cancel
            </button>
            <button className="btn btn-primary" type="submit" disabled={busy}>
              {busy ? "Changing…" : "Change password"}
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
