"use client";
import type { User } from "firebase/auth";
import { type FormEvent, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { suggestUsername, UsernameField, useUsernameCheck } from "./UsernameField";

/**
 * Picking a username: the step the app shows a new account
 * (/welcome/username), started from their name and theirs to change.
 * Claimed through the API, which also starts the profile, so the player
 * can be found and followed. A card on Home for older accounts; a step of
 * sign-up (PersonalGate) for new ones that signed up with Google or Apple.
 */
export function UsernameStep({ user, onDone, step = false }: { user: User; onDone: () => void; step?: boolean }) {
  const [name, setName] = useState(() => suggestUsername(user.displayName));
  const check = useUsernameCheck(name, user.uid);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (check.status !== "available" && check.status !== "failed") return;
    setBusy(true);
    setError("");
    try {
      await callApi(user, "/v1/me/username", { method: "POST", body: { username: check.handle } });
      onDone();
    } catch (err) {
      if (err instanceof ApiError && err.code === "already_exists") check.markTaken();
      else setError(err instanceof ApiError ? err.message : "Something went wrong. Try again.");
    } finally {
      setBusy(false);
    }
  }

  const ready = check.status === "available" || check.status === "failed";
  return (
    <form className={step ? "username-step-form" : "card username-step"} onSubmit={(e) => void submit(e)} noValidate>
      {!step && (
        <>
          <h2 className="card-title">Pick your username</h2>
          <p className="muted small">It&apos;s how teammates find you.</p>
        </>
      )}
      <UsernameField value={name} onChange={setName} check={check} />
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
