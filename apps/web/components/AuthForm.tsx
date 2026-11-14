"use client";
import { FirebaseError } from "firebase/app";
import {
  createUserWithEmailAndPassword,
  GoogleAuthProvider,
  OAuthProvider,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signInWithPopup,
  updateProfile,
} from "firebase/auth";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { type FormEvent, useEffect, useState } from "react";
import { authConfigured, emailForUsername, firebaseAuth } from "@/lib/firebase";
import { ApiError, callApi } from "@/lib/client";
import { signupDraft } from "@/lib/signupDraft";
import { useAuth } from "./AuthProvider";
import { localToday, signUpBirthDateProblem } from "./PersonalDetailsForm";
import { SignUpSteps } from "./SignUpSteps";
import { suggestUsername, UsernameField, useUsernameCheck } from "./UsernameField";

/** Firebase's error codes in words. */
function message(e: unknown): string {
  const code = e instanceof FirebaseError ? e.code : "";
  // Username sign-in (account-signInEmail) words its own failures.
  // The Functions SDK adds the HTTP status (" [401]"); people don't need it.
  if (code.startsWith("functions/") && e instanceof FirebaseError && e.message) {
    return e.message.replace(/\s*\[\d{3}\]$/, "");
  }
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
      return "Enter the email address of your account.";
    case "auth/too-many-requests":
      return "Too many tries. Wait a minute and try again.";
    case "auth/popup-closed-by-user":
    case "auth/cancelled-popup-request":
      return "";
    case "auth/unauthorized-domain":
      return "Signing in isn't set up for this web address yet.";
    case "auth/operation-not-allowed":
      return "That way of signing in isn't turned on yet.";
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


/**
 * Log in, or sign up's first step (account details, as in the app's
 * SignUpScreen): name, a username they can change (suggested from the name
 * until they edit it), birthday, email and password. Under 13 is refused
 * before any account exists. Google and Apple skip the form; PersonalGate
 * then asks their username and, like everyone, the details ("About you").
 */
export function AuthForm({ mode }: { mode: "sign-in" | "sign-up" }) {
  const router = useRouter();
  const next = safeNext(useSearchParams().get("next"));
  const { user } = useAuth();
  const [first, setFirst] = useState("");
  const [last, setLast] = useState("");
  const [username, setUsername] = useState("");
  const [usernameEdited, setUsernameEdited] = useState(false);
  const [birthDate, setBirthDate] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const signUp = mode === "sign-up";
  const shownUsername = usernameEdited ? username : suggestUsername(`${first} ${last}`);
  const check = useUsernameCheck(signUp ? shownUsername : "", null);

  // Not while sign-up is still claiming the username.
  useEffect(() => {
    if (user && !busy) router.replace(next);
  }, [user, busy, next, router]);

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

  function fail(text: string, field?: string) {
    setError(text);
    if (field) document.getElementById(field)?.focus();
  }

  function submit(e: FormEvent) {
    e.preventDefault();
    if (!signUp) {
      void run(async () => {
        // A username (no @) is swapped for its email by account-signInEmail,
        // which checks the password first, as in the app.
        const id = email.trim();
        const address = id.includes("@") ? id : await emailForUsername(id, password);
        await signInWithEmailAndPassword(auth, address, password);
      });
      return;
    }
    if (!first.trim()) return fail("Enter your first name.", "su-first");
    if (!last.trim()) return fail("Enter your last name.", "su-last");
    if (check.status === "empty") return fail("Pick a username.", "su-username");
    if (check.status === "invalid" || check.status === "taken") {
      return fail(check.message ?? "Pick another username.", "su-username");
    }
    if (check.status === "checking") return fail("Still checking that username. Try again in a moment.");
    const ageProblem = signUpBirthDateProblem(birthDate);
    if (ageProblem) return fail(ageProblem, "su-birth");
    if (!email.trim().includes("@")) return fail("Enter your email address.", "su-email");
    if (password.length < 6) return fail("Use a password of at least 6 characters.", "su-password");
    signupDraft.setBirthDate(birthDate);
    void run(async () => {
      const cred = await createUserWithEmailAndPassword(auth, email.trim(), password);
      await updateProfile(cred.user, { displayName: `${first.trim()} ${last.trim()}` });
      try {
        await callApi(cred.user, "/v1/me/username", { method: "POST", body: { username: check.handle } });
      } catch (err) {
        // Taken in the meantime, or the API is down: the next step asks again.
        if (!(err instanceof ApiError)) throw err;
      }
    });
  }

  const oauth = (
    <div className="auth-oauth">
      <button
        className="btn auth-google"
        type="button"
        disabled={busy}
        onClick={() => run(() => signInWithPopup(auth, new GoogleAuthProvider()))}
      >
        Continue with Google
      </button>
      <button
        className="btn auth-google"
        type="button"
        disabled={busy}
        onClick={() =>
          run(() => {
            const apple = new OAuthProvider("apple.com");
            apple.addScope("email");
            apple.addScope("name");
            return signInWithPopup(auth, apple);
          })
        }
      >
        Continue with Apple
      </button>
    </div>
  );

  const alerts = (
    <>
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
    </>
  );

  if (!signUp) {
    return (
      <div className="auth-card">
        <header className="auth-head">
          <h1>Welcome back</h1>
          <p>Log in to get back to your teams, games and people.</p>
        </header>
        {oauth}
        <p className="auth-or">
          <span>or</span>
        </p>
        <form onSubmit={submit}>
          <label>
            Email or username
            <input
              type="text"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="username"
              autoCapitalize="none"
              spellCheck={false}
            />
          </label>
          <div className="auth-field">
            <span className="label-row">
              <label htmlFor="si-password">Password</label>
              <button
                className="link-button small"
                type="button"
                disabled={busy}
                onClick={() =>
                  run(async () => {
                    if (!email.trim().includes("@")) throw new FirebaseError("auth/invalid-email", "");
                    await sendPasswordResetEmail(auth, email.trim());
                    setNotice("If there's an account with that email, we've sent a link to reset its password.");
                  })
                }
              >
                Forgot your password?
              </button>
            </span>
            <input
              id="si-password"
              type="password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
            />
          </div>
          {alerts}
          <button className="btn btn-primary" type="submit" disabled={busy}>
            {busy ? "Logging in…" : "Log in"}
          </button>
        </form>
        <p className="auth-alt">
          New to Stall 10? <Link href={`/sign-up?next=${encodeURIComponent(next)}`}>Create an account</Link>
        </p>
      </div>
    );
  }

  return (
    <div className="auth-card auth-card-wide">
      <SignUpSteps at={1} />
      <header className="auth-head">
        <h1>Create your account</h1>
        <p>It&apos;s free. Next we&apos;ll ask a few details about you.</p>
      </header>
      {oauth}
      <p className="auth-or">
        <span>or sign up with email</span>
      </p>
      <form onSubmit={submit} noValidate>
        <div className="form-grid">
          <label>
            First name
            <input id="su-first" value={first} onChange={(e) => setFirst(e.target.value)} autoComplete="given-name" maxLength={30} />
          </label>
          <label>
            Last name
            <input id="su-last" value={last} onChange={(e) => setLast(e.target.value)} autoComplete="family-name" maxLength={30} />
          </label>
        </div>
        <UsernameField
          inputId="su-username"
          value={shownUsername}
          onChange={(v) => {
            setUsernameEdited(true);
            setUsername(v);
            setError("");
          }}
          check={check}
          hint="Suggested from your name. Change it to anything you like."
        />
        <label>
          Date of birth
          <input
            id="su-birth"
            type="date"
            value={birthDate}
            max={localToday()}
            min="1900-01-01"
            autoComplete="bday"
            onChange={(e) => {
              setBirthDate(e.target.value);
              setError("");
            }}
          />
          <small className="muted">Only you see it. We ask so we can follow the rules for younger players.</small>
        </label>
        <label>
          Email
          <input
            id="su-email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="email"
            autoCapitalize="none"
            spellCheck={false}
          />
        </label>
        <label>
          Password
          <input
            id="su-password"
            type="password"
            minLength={6}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="new-password"
          />
          <small className="muted">At least 6 characters.</small>
        </label>
        {alerts}
        <button className="btn btn-primary" type="submit" disabled={busy}>
          {busy ? "Creating your account…" : "Continue"}
        </button>
      </form>
      <p className="auth-alt">
        Already have an account? <Link href={`/sign-in?next=${encodeURIComponent(next)}`}>Log in</Link>
        <br />
        By signing up you agree to the <Link href="/terms">Terms of Service</Link> and{" "}
        <Link href="/privacy">Privacy Policy</Link>.
      </p>
    </div>
  );
}
