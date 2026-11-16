"use client";
import { asksForName, joinPersonName, type IdentityResult, personNameLimits, splitDisplayName } from "@stall10/shared";
import type { User } from "firebase/auth";
import { type FormEvent, useState } from "react";
import { ApiError, callApi, problem } from "@/lib/client";
import { signupDraft } from "@/lib/signupDraft";
import { suggestUsername, UsernameField, useUsernameCheck } from "./UsernameField";

/** Whether [user] signs in with a password (an email account). */
const hasPassword = (user: User) => user.providerData.some((p) => p.providerId === "password");

/**
 * Whether the step asks their name: always when the username is already
 * theirs (then it's shown only for a missing name), else for Google and
 * Apple accounts and accounts without a name (the app's
 * ChooseUsernameViewModel.asksName).
 */
export const stepAsksName = (user: User, needsUsername: boolean) =>
  !needsUsername || asksForName(user.displayName, hasPassword(user));

/** The step's heading: the same words as the app's ChooseUsernameScreen. */
export function usernameStepCopy(askName: boolean, needsUsername: boolean): { title: string; subtitle: string } {
  if (askName && needsUsername) {
    return {
      title: "Your name and username",
      subtitle:
        "Your name shows on your profile, posts and team rosters. Your username is how teammates find and mention you, as @name.",
    };
  }
  if (askName) return { title: "Your name", subtitle: "It shows on your profile, posts and team rosters." };
  return {
    title: "Pick your username",
    subtitle: "It's how teammates find and mention you. We started one from your name; change it to anything you like.",
  };
}

/**
 * Picking a username: the step the app shows a new account
 * (/welcome/username), started from their name and theirs to change.
 * Google and Apple accounts, and accounts without a name, give their first
 * and last name here too (started from Google's or Apple's): it's the name
 * on their profile, posts and rosters. The name is saved through
 * `PUT /v1/me/identity` (the Auth record and the profile, as Settings
 * renames), then the username is claimed through the API, which also
 * starts the profile, so the player can be found and followed. A card on
 * Home for older accounts; a step of sign-up (PersonalGate) for new ones.
 */
export function UsernameStep({
  user,
  onDone,
  step = false,
  needsUsername = true,
}: {
  user: User;
  onDone: () => void;
  step?: boolean;
  /** False when they have a username and only the name is missing. */
  needsUsername?: boolean;
}) {
  const [askName] = useState(() => stepAsksName(user, needsUsername));
  const [start] = useState(() => splitDisplayName(user.displayName));
  const [first, setFirst] = useState(start.first);
  const [last, setLast] = useState(start.last);
  const [typed, setTyped] = useState<string | null>(null);
  // Suggested from the name until they edit it, as on the sign-up form.
  const shown = typed ?? suggestUsername(askName ? joinPersonName(first, last) : user.displayName);
  const check = useUsernameCheck(needsUsername ? shown : "", user.uid);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  function fail(text: string, field: string) {
    setError(text);
    document.getElementById(field)?.focus();
  }

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (askName && !first.trim()) return fail("Enter your first name.", "us-first");
    if (askName && !last.trim()) return fail("Enter your last name.", "us-last");
    if (needsUsername && check.status !== "available" && check.status !== "failed") return;
    setBusy(true);
    setError("");
    try {
      if (askName) {
        const name = joinPersonName(first, last);
        // "About you" starts the legal name from these boxes.
        signupDraft.setName(first, last);
        if (name !== (user.displayName ?? "").trim()) {
          await callApi<IdentityResult>(user, "/v1/me/identity", { method: "PUT", body: { name } });
          // The claim and the gate read the Auth record's new name.
          await user.reload();
        }
      }
      if (needsUsername) {
        await callApi(user, "/v1/me/username", { method: "POST", body: { username: check.handle } });
      }
      onDone();
    } catch (err) {
      if (err instanceof ApiError && err.code === "already_exists") check.markTaken();
      else setError(problem(err));
    } finally {
      setBusy(false);
    }
  }

  const ready = !needsUsername || check.status === "available" || check.status === "failed";
  const copy = usernameStepCopy(askName, needsUsername);
  return (
    <form className={step ? "username-step-form" : "card username-step"} onSubmit={(e) => void submit(e)} noValidate>
      {!step && (
        <>
          <h2 className="card-title">{copy.title}</h2>
          <p className="muted small">{askName ? copy.subtitle : "It's how teammates find you."}</p>
        </>
      )}
      {askName && (
        <div className="form-grid">
          <label>
            First name
            <input
              id="us-first"
              value={first}
              onChange={(e) => {
                setFirst(e.target.value);
                setError("");
              }}
              autoComplete="given-name"
              maxLength={personNameLimits.first}
            />
          </label>
          <label>
            Last name
            <input
              id="us-last"
              value={last}
              onChange={(e) => {
                setLast(e.target.value);
                setError("");
              }}
              autoComplete="family-name"
              maxLength={personNameLimits.last}
            />
          </label>
        </div>
      )}
      {needsUsername && (
        <UsernameField
          inputId="us-username"
          value={shown}
          onChange={(v) => {
            setTyped(v);
            setError("");
          }}
          check={check}
          hint={askName ? "Suggested from your name. Change it to anything you like." : undefined}
        />
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      <button className={step ? "btn btn-primary" : "btn btn-primary btn-small"} type="submit" disabled={busy || !ready}>
        {busy ? "Saving…" : step ? "Continue" : "Save"}
      </button>
    </form>
  );
}
