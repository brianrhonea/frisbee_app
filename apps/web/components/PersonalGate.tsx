"use client";
import { type AgreementStatus, agreementPath, minimumAge, nameMissing, type PersonalDetailsResponse, type PersonalDetailsStatus } from "@stall10/shared";
import type { User } from "firebase/auth";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { createContext, type ReactNode, useCallback, useContext, useEffect, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { deleteOwnAccount } from "@/lib/firebase";
import { useLiveDoc } from "@/lib/live";
import { signupDraft } from "@/lib/signupDraft";
import { useAuth } from "./AuthProvider";
import { AgreeTerms } from "./AgreeTerms";
import { PersonalDetailsForm } from "./PersonalDetailsForm";
import "./member.css";
import { SignUpSteps } from "./SignUpSteps";
import { ErrorNote } from "./StatusViews";
import { stepAsksName, UsernameStep, usernameStepCopy } from "./UsernameStep";

/** Readable without finishing sign-up: the legal pages and help. */
const open = ["/terms", "/privacy", "/cookies", "/guidelines", "/help", "/about", "/delete-account", "/sign-in", "/sign-up"];

const Ctx = createContext<{ status: PersonalDetailsStatus | null; refresh: () => void }>({
  status: null,
  refresh: () => {},
});

/** Whether the signed-in member has given their personal details. */
export const usePersonalStatus = () => useContext(Ctx);

/** A 200 that isn't the shape we need is a failed check, never a pass. */
const validStatus = (s: unknown): s is PersonalDetailsStatus =>
  !!s && typeof s === "object" && typeof (s as PersonalDetailsStatus).complete === "boolean" && typeof (s as PersonalDetailsStatus).required === "boolean";
const validAgreement = (a: unknown): a is AgreementStatus =>
  !!a && typeof a === "object" && typeof (a as AgreementStatus).agreed === "boolean";

const dismissKey = (uid: string) => `stall10.personalPrompt.${uid}`;
function dismissed(uid: string): boolean {
  try {
    return localStorage.getItem(dismissKey(uid)) === "1";
  } catch {
    return false;
  }
}

/**
 * Around every page. A new account (made since personalDetailsRequiredSince)
 * that hasn't given its details sees only the form until it does; older
 * accounts get a card they can dismiss (that dismissal covers only that
 * card). The gate fails closed: if the personal status or the Terms
 * agreement can't be read (API error), the member sees a blocking "Couldn't
 * check your account" state with a retry instead of the app, so an outage
 * can't skip Terms or the birth date. The legal pages stay readable. While
 * a first answer is still loading nothing is held up.
 */
export function PersonalGate({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const path = usePathname();
  const [status, setStatus] = useState<PersonalDetailsStatus | null>(null);
  // The Community Guidelines and Terms: null while unknown (nobody waits).
  const [agreed, setAgreed] = useState<boolean | null>(null);
  const [hidePrompt, setHidePrompt] = useState(false);
  // A check failed: the member is held at a retry, never let through.
  const [statusFailed, setStatusFailed] = useState(false);
  const [agreeFailed, setAgreeFailed] = useState(false);
  // Under 13: the account is removed and signed out, and this stays up.
  const [tooYoung, setTooYoung] = useState<"removing" | "removed" | null>(null);
  // Bumped when the name step saves: reloading the user changes its
  // displayName in place, which on its own doesn't re-render.
  const [, setNamed] = useState(0);

  // Only the latest request answers: a slow one for the last account (or
  // an earlier refresh) never overwrites a newer status.
  const latest = useRef(0);
  const load = useCallback((u: User) => {
    const mine = ++latest.current;
    callApi<PersonalDetailsStatus>(u, "/v1/me/personal/status").then(
      (s) => {
        if (mine !== latest.current) return;
        if (!validStatus(s)) {
          setStatus(null);
          setStatusFailed(true);
          return;
        }
        setStatus(s);
        setStatusFailed(false);
      },
      () => {
        if (mine !== latest.current) return;
        setStatus(null);
        setStatusFailed(true);
      },
    );
  }, []);

  const agreeLatest = useRef(0);
  const loadAgreement = useCallback((u: User) => {
    const mine = ++agreeLatest.current;
    callApi<AgreementStatus>(u, agreementPath).then(
      (a) => {
        if (mine !== agreeLatest.current) return;
        if (!validAgreement(a)) {
          setAgreed(null);
          setAgreeFailed(true);
          return;
        }
        setAgreed(a.agreed);
        setAgreeFailed(false);
      },
      () => {
        if (mine !== agreeLatest.current) return;
        setAgreed(null);
        setAgreeFailed(true);
      },
    );
  }, []);
  useEffect(() => {
    latest.current += 1;
    agreeLatest.current += 1;
    setStatus(null);
    setAgreed(null);
    setStatusFailed(false);
    setAgreeFailed(false);
    if (!user) return;
    setHidePrompt(dismissed(user.uid));
    load(user);
    loadAgreement(user);
    return () => {
      // Invalidate in-flight answers for this account.
      latest.current += 1;
      agreeLatest.current += 1;
    };
  }, [user, load, loadAgreement]);

  const refresh = useCallback(() => {
    if (user) load(user);
  }, [user, load]);

  // Retries only what failed.
  const retry = useCallback(() => {
    if (!user) return;
    if (statusFailed) load(user);
    if (agreeFailed) loadAgreement(user);
  }, [user, statusFailed, agreeFailed, load, loadAgreement]);

  const openPath = open.some((p) => path === p || path.startsWith(`${p}/`));
  // A new account finishes sign-up first: its name and username (Google
  // and Apple skip the form that asks them; Apple can hide the name), then
  // its details.
  const newAccount = !!user && status?.required === true;
  const profile = useLiveDoc<{ username?: string }>(newAccount ? `profiles/${user!.uid}` : null);
  const profileKnown = newAccount && profile.data !== undefined;
  const needsUsername = profileKnown && !profile.data?.username;
  const needsName = profileKnown && nameMissing(user!.displayName);
  const missing = !!user && status !== null && !status.complete;
  const blocked = missing && status.required && !openPath;
  const checkFailed = !!user && (statusFailed || agreeFailed) && !openPath;
  const prompt = missing && !status.required && !hidePrompt && path !== "/settings/personal";

  return (
    <Ctx.Provider value={{ status, refresh }}>
      {tooYoung ? (
        <div className="auth-card" role="alert">
          <h1>Sorry, you&apos;re too young</h1>
          <p>
            You must be {minimumAge} or older to use Stall 10.{" "}
            {tooYoung === "removing"
              ? "Removing the account…"
              : "We didn't keep your details, and the account has been removed."}
          </p>
          {tooYoung === "removed" && (
            <Link className="btn" href="/">
              Back to Stall 10
            </Link>
          )}
        </div>
      ) : checkFailed ? (
        <div className="auth-card">
          <h1>Couldn&apos;t check your account</h1>
          <ErrorNote onRetry={retry}>We couldn&apos;t confirm your account details. Check your connection and retry.</ErrorNote>
        </div>
      ) : (needsUsername || needsName) && !openPath && user ? (
        <NameStep user={user} needsUsername={needsUsername} onDone={() => setNamed((n) => n + 1)} />
      ) : agreed === false && !openPath && user ? (
        <AgreeTerms user={user} onDone={() => setAgreed(true)} />
      ) : blocked && user ? (
        <FinishSignUp
          user={user}
          onDone={refresh}
          onTooYoung={() => {
            setTooYoung("removing");
            void deleteOwnAccount().finally(() => setTooYoung("removed"));
          }}
        />
      ) : (
        <>
          {prompt && user && (
            <div className="card personal-prompt" role="region" aria-label="Complete your details">
              <div>
                <b>Complete your details</b>
                <p className="muted small">
                  Add your legal name, birthday and contact details. Only you can see them, and we keep them encrypted.
                </p>
              </div>
              <div className="personal-prompt-actions">
                <Link className="btn btn-primary btn-small" href="/settings/personal">
                  Add details
                </Link>
                <button
                  className="link-button small"
                  type="button"
                  onClick={() => {
                    setHidePrompt(true);
                    try {
                      localStorage.setItem(dismissKey(user.uid), "1");
                    } catch {
                      // Shown again next visit; fine.
                    }
                  }}
                >
                  Not now
                </button>
              </div>
            </div>
          )}
          {children}
        </>
      )}
    </Ctx.Provider>
  );
}

/** Sign-up's first step for accounts that skipped the form: "Your name and username". */
function NameStep({ user, needsUsername, onDone }: { user: User; needsUsername: boolean; onDone: () => void }) {
  const [askName] = useState(() => stepAsksName(user, needsUsername));
  const copy = usernameStepCopy(askName, needsUsername);
  return (
    <div className="page">
      <div className="auth-card auth-card-wide">
        <SignUpSteps at={1} />
        <header className="auth-head">
          <h1>{copy.title}</h1>
          <p>{copy.subtitle}</p>
        </header>
        <UsernameStep user={user} step needsUsername={needsUsername} onDone={onDone} />
      </div>
    </div>
  );
}

/** The sign-up form's last step, until it's done. */
function FinishSignUp({ user, onDone, onTooYoung }: { user: User; onDone: () => void; onTooYoung: () => void }) {
  const [draftBirthDate] = useState(() => signupDraft.takeBirthDate());
  // The first and last name just typed (sign-up or the name step), else
  // the account's name split.
  const [name] = useState(() => signupDraft.takeName());
  // The birthday saved at sign-up (PUT /v1/me/personal/birth-date), so it
  // isn't asked again after a reload or on another device; else the one
  // still in memory. The form starts once this has answered (or failed).
  const [saved, setSaved] = useState<{ birthDate?: string } | null>(null);
  useEffect(() => {
    let live = true;
    callApi<PersonalDetailsResponse>(user, "/v1/me/personal").then(
      (r) => live && setSaved({ birthDate: r.signUpBirthDate ?? r.details?.birthDate }),
      () => live && setSaved({}),
    );
    return () => {
      live = false;
    };
  }, [user]);
  const birthDate = saved?.birthDate ?? draftBirthDate;
  return (
    <div className="page">
      <div className="card personal-finish">
        <SignUpSteps at={2} />
        <header className="auth-head">
          <h1>About you</h1>
          <p>A few details for club age checks and tournament signups. Your profile shows only your name and username.</p>
        </header>
        {saved ? (
          <PersonalDetailsForm
            user={user}
            email={user.email}
            initial={null}
            prefill={{ name: user.displayName, first: name?.first, last: name?.last, birthDate }}
            submitLabel="Continue"
            onSaved={onDone}
            onTooYoung={onTooYoung}
          />
        ) : (
          <p className="muted">Loading…</p>
        )}
      </div>
    </div>
  );
}
