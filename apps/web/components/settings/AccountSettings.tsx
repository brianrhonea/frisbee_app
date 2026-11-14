"use client";
import { FirebaseError } from "firebase/app";
import {
  EmailAuthProvider,
  GoogleAuthProvider,
  OAuthProvider,
  reauthenticateWithCredential,
  reauthenticateWithPopup,
} from "firebase/auth";
import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";
import { deleteOwnAccount } from "@/lib/firebase";
import { useAuth } from "../AuthProvider";

type Method = "password" | "google.com" | "apple.com";
const methodNames: Record<Method, string> = { password: "email and password", "google.com": "Google", "apple.com": "Apple" };

/** How they signed in, for confirming it's them. */
function methodOf(providers: string[]): Method | null {
  for (const m of ["password", "google.com", "apple.com"] as const) if (providers.includes(m)) return m;
  return null;
}

function problem(e: unknown): string {
  const code = e instanceof FirebaseError ? e.code : "";
  if (code === "auth/wrong-password" || code === "auth/invalid-credential") return "That password isn't right.";
  if (code === "auth/popup-closed-by-user" || code === "auth/cancelled-popup-request") return "";
  if (code === "auth/too-many-requests") return "Too many tries. Wait a minute and try again.";
  if (code === "functions/failed-precondition") return "Confirm it's you again, then delete your account.";
  return "Couldn't delete your account. Try again, or contact us.";
}

/** Settings → Account: who they're signed in as, and deleting the account and its data. */
export function AccountSettings() {
  const { user } = useAuth();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  if (!user) return null;
  const me = user;
  const method = methodOf(me.providerData.map((p) => p.providerId));

  async function remove(e: FormEvent) {
    e.preventDefault();
    if (confirm.trim().toUpperCase() !== "DELETE") return setError("Type DELETE to confirm.");
    setBusy(true);
    setError("");
    try {
      // account-deleteAccount needs a sign-in from the last few minutes.
      if (method === "password") {
        await reauthenticateWithCredential(me, EmailAuthProvider.credential(me.email ?? "", password));
      } else if (method === "google.com") {
        await reauthenticateWithPopup(me, new GoogleAuthProvider());
      } else if (method === "apple.com") {
        await reauthenticateWithPopup(me, new OAuthProvider("apple.com"));
      }
      await deleteOwnAccount({ loginOnlyFallback: false });
      router.replace("/");
    } catch (err) {
      setError(problem(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="stack">
      <div className="card">
        <h2 className="card-title">Account</h2>
        <p>
          Signed in as <b>{me.email ?? me.displayName}</b>
          {method && <span className="muted"> with {methodNames[method]}</span>}.
        </p>
      </div>
      <div className="card danger-zone">
        <h2 className="card-title">Delete account</h2>
        <p className="muted small">
          This deletes your account and what you&apos;ve put in Stall 10: your profile, personal details, posts,
          comments, messages, event responses and join requests. You leave every team; a team you own passes to its next
          admin. Messages other people sent you stay, under &quot;Deleted user&quot;. It can&apos;t be undone.
        </p>
        {!open ? (
          <button className="btn btn-danger" type="button" onClick={() => setOpen(true)}>
            Delete account…
          </button>
        ) : (
          <form className="settings-form" onSubmit={(e) => void remove(e)}>
            {method === "password" ? (
              <label>
                Your password
                <input
                  type="password"
                  required
                  value={password}
                  autoComplete="current-password"
                  onChange={(e) => setPassword(e.target.value)}
                />
              </label>
            ) : (
              method && <p className="muted small">You&apos;ll confirm it&apos;s you with {methodNames[method]}.</p>
            )}
            <label>
              Type DELETE to confirm
              <input value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="off" />
            </label>
            <div className="form-actions">
              {error && (
                <span className="form-error" role="alert">
                  {error}
                </span>
              )}
              <button className="btn" type="button" disabled={busy} onClick={() => setOpen(false)}>
                Cancel
              </button>
              <button className="btn btn-danger" type="submit" disabled={busy}>
                {busy ? "Deleting…" : "Delete my account"}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
