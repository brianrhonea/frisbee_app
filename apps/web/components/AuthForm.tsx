"use client";
import { FirebaseError } from "firebase/app";
import {
  createUserWithEmailAndPassword,
  GoogleAuthProvider,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signInWithPopup,
  updateProfile,
} from "firebase/auth";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { type FormEvent, useEffect, useState } from "react";
import { authConfigured, firebaseAuth } from "@/lib/firebase";
import { signupDraft } from "@/lib/signupDraft";
import { useAuth } from "./AuthProvider";
import { localToday, signUpBirthDateProblem } from "./PersonalDetailsForm";

/** Firebase's error codes in words. */
function message(e: unknown): string {
  const code = e instanceof FirebaseError ? e.code : "";
  switch (code) {
    case "auth/invalid-credential":
    case "auth/wrong-password":
    case "auth/user-not-found":
      return "That email and password don't match an account.";
    case "auth/email-already-in-use":
      return "There's already an account with that email. Log in instead.";
    case "auth/weak-password":
      return "Use a password of at least 6 characters.";
    case "auth/invalid-email":
      return "That doesn't look like an email address.";
    case "auth/too-many-requests":
      return "Too many tries. Wait a minute and try again.";
    case "auth/popup-closed-by-user":
    case "auth/cancelled-popup-request":
      return "";
    case "auth/unauthorized-domain":
      return "Signing in isn't set up for this web address yet.";
    default:
      return "Something went wrong. Try again.";
  }
}

/** Only same-site paths, so a link can't send people elsewhere after signing in. */
function safeNext(next: string | null): string {
  // Not "//host" or "/\host" (browsers treat both as another site), and
  // no backslashes anywhere.
  return next && next.startsWith("/") && !next.startsWith("//") && !next.includes("\\") ? next : "/";
}

export function AuthForm({ mode }: { mode: "sign-in" | "sign-up" }) {
  const router = useRouter();
  const next = safeNext(useSearchParams().get("next"));
  const { user } = useAuth();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  // Sign-up asks the birthday first, so nobody under 13 gets an account.
  const [birthDate, setBirthDate] = useState("");
  const [ageChecked, setAgeChecked] = useState(false);

  useEffect(() => {
    if (user) router.replace(next);
  }, [user, next, router]);

  if (!authConfigured) {
    return <p className="form-error">Signing in isn&apos;t set up on this copy of the website yet.</p>;
  }
  const auth = firebaseAuth()!;

  async function run(action: () => Promise<unknown>) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await action();
    } catch (e) {
      setError(message(e));
    } finally {
      setBusy(false);
    }
  }

  function submit(e: FormEvent) {
    e.preventDefault();
    void run(async () => {
      if (mode === "sign-in") {
        await signInWithEmailAndPassword(auth, email.trim(), password);
      } else {
        const cred = await createUserWithEmailAndPassword(auth, email.trim(), password);
        if (name.trim()) await updateProfile(cred.user, { displayName: name.trim() });
      }
    });
  }

  if (mode === "sign-up" && !ageChecked) {
    const checkAge = (e: FormEvent) => {
      e.preventDefault();
      const problem = signUpBirthDateProblem(birthDate);
      if (problem) return setError(problem);
      signupDraft.setBirthDate(birthDate);
      setError("");
      setAgeChecked(true);
    };
    return (
      <div className="auth-card">
        <h1>Create your account</h1>
        <form onSubmit={checkAge} noValidate>
          <label>
            Date of birth
            <input
              type="date"
              required
              value={birthDate}
              max={localToday()}
              min="1900-01-01"
              autoComplete="bday"
              onChange={(e) => {
                setBirthDate(e.target.value);
                setError("");
              }}
            />
            <small className="muted">Only you will see it. We ask so we can follow the rules for younger players.</small>
          </label>
          {error && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
          <button className="btn btn-primary" type="submit">
            Continue
          </button>
        </form>
        <p className="auth-alt">
          Already have an account? <Link href={`/sign-in?next=${encodeURIComponent(next)}`}>Log in</Link>
        </p>
      </div>
    );
  }

  return (
    <div className="auth-card">
      <h1>{mode === "sign-in" ? "Log in" : "Create your account"}</h1>
      <button
        className="btn auth-google"
        type="button"
        disabled={busy}
        onClick={() => run(() => signInWithPopup(auth, new GoogleAuthProvider()))}
      >
        Continue with Google
      </button>
      <p className="auth-or">or</p>
      <form onSubmit={submit}>
        {mode === "sign-up" && (
          <label>
            Name on your profile
            <input value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" maxLength={60} />
            <small className="muted">Other players see this. Your legal name comes next and stays private.</small>
          </label>
        )}
        <label>
          Email
          <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
        </label>
        <label>
          Password
          <input
            type="password"
            required
            minLength={6}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete={mode === "sign-in" ? "current-password" : "new-password"}
          />
        </label>
        {error && <p className="form-error" role="alert">{error}</p>}
        {notice && <p className="form-notice" role="status">{notice}</p>}
        <button className="btn btn-primary" type="submit" disabled={busy}>
          {mode === "sign-in" ? "Log in" : "Sign up"}
        </button>
      </form>
      {mode === "sign-in" ? (
        <p className="auth-alt">
          <button
            className="link-button"
            type="button"
            disabled={busy}
            onClick={() =>
              run(async () => {
                if (!email.trim()) throw new FirebaseError("auth/invalid-email", "");
                await sendPasswordResetEmail(auth, email.trim());
                setNotice("If there's an account with that email, we've sent a link to reset its password.");
              })
            }
          >
            Forgot your password?
          </button>
          <br />
          New to Stall 10? <Link href={`/sign-up?next=${encodeURIComponent(next)}`}>Sign up</Link>
        </p>
      ) : (
        <p className="auth-alt">
          Already have an account? <Link href={`/sign-in?next=${encodeURIComponent(next)}`}>Log in</Link>
          <br />
          By signing up you agree to the <Link href="/terms">Terms of Service</Link> and{" "}
          <Link href="/privacy">Privacy Policy</Link>.
        </p>
      )}
    </div>
  );
}
