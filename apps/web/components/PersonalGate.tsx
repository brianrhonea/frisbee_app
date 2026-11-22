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
import { stepAsksName, UsernameStep, usernameStepCopy } from "./UsernameStep";

/** Readable without finishing sign-up: the legal pages and help. */
const open = ["/terms", "/privacy", "/cookies", "/guidelines", "/help", "/about", "/delete-account", "/sign-in", "/sign-up"];

const Ctx = createContext<{ status: PersonalDetailsStatus | null; refresh: () => void }>({
  status: null,
  refresh: () => {},
});

/** Whether the signed-in member has given their personal details. */
export const usePersonalStatus = () => useContext(Ctx);

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
 * accounts get a card they can dismiss. If the status can't be read (the
 * API is down, or this site's API has no encryption key), nobody is held
 * up: the gate only stops someone on a definite "required and missing".
 */
export function PersonalGate({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const path = usePathname();
  const [status, setStatus] = useState<PersonalDetailsStatus | null>(null);
  // The Community Guidelines and Terms: null while unknown (nobody waits).
  const [agreed, setAgreed] = useState<boolean | null>(null);
  const [hidePrompt, setHidePrompt] = useState(false);
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
      (s) => mine === latest.current && setStatus(s),
      () => mine === latest.current && setStatus(null),
    );
  }, []);

  useEffect(() => {
    latest.current += 1;
    setStatus(null);
    setAgreed(null);
    if (!user) return;
    setHidePrompt(dismissed(user.uid));
    load(user);
    let live = true;
    callApi<AgreementStatus>(user, agreementPath).then(
      (a) => live && setAgreed(a.agreed),
      () => live && setAgreed(null),
    );
    return () => {
      live = false;
    };
  }, [user, load]);

  const refresh = useCallback(() => {
    if (user) load(user);
  }, [user, load]);

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
