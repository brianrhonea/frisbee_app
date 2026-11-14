"use client";
import { minimumAge, type PersonalDetailsStatus } from "@stall10/shared";
import type { User } from "firebase/auth";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { createContext, type ReactNode, useCallback, useContext, useEffect, useState } from "react";
import { callApi } from "@/lib/client";
import { deleteOwnAccount } from "@/lib/firebase";
import { signupDraft } from "@/lib/signupDraft";
import { useAuth } from "./AuthProvider";
import { PersonalDetailsForm } from "./PersonalDetailsForm";

/** Readable without finishing sign-up: the legal pages and help. */
const open = ["/terms", "/privacy", "/cookies", "/help", "/about", "/delete-account", "/sign-in", "/sign-up"];

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
  const [hidePrompt, setHidePrompt] = useState(false);
  // Under 13: the account is removed and signed out, and this stays up.
  const [tooYoung, setTooYoung] = useState<"removing" | "removed" | null>(null);

  const load = useCallback((u: User) => {
    callApi<PersonalDetailsStatus>(u, "/v1/me/personal/status")
      .then(setStatus)
      .catch(() => setStatus(null));
  }, []);

  useEffect(() => {
    setStatus(null);
    if (user) {
      setHidePrompt(dismissed(user.uid));
      load(user);
    }
  }, [user, load]);

  const refresh = useCallback(() => {
    if (user) load(user);
  }, [user, load]);

  const missing = !!user && status !== null && !status.complete;
  const blocked = missing && status.required && !open.some((p) => path === p || path.startsWith(`${p}/`));
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

/** The sign-up form's last step, until it's done. */
function FinishSignUp({ user, onDone, onTooYoung }: { user: User; onDone: () => void; onTooYoung: () => void }) {
  const [birthDate] = useState(() => signupDraft.takeBirthDate());
  return (
    <div className="page">
      <div className="card personal-finish">
        <h1>Finish signing up</h1>
        <p className="muted">
          Like a USA Ultimate membership, Stall 10 needs a few details about you. Your profile shows only your name and
          username.
        </p>
        <PersonalDetailsForm
          user={user}
          email={user.email}
          initial={null}
          prefill={{ name: user.displayName, birthDate }}
          submitLabel="Continue"
          onSaved={onDone}
          onTooYoung={onTooYoung}
        />
      </div>
    </div>
  );
}
