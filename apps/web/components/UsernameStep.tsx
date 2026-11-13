"use client";
import { normalizeUsername, usernameProblem } from "@stall10/shared";
import type { User } from "firebase/auth";
import { type FormEvent, useState } from "react";
import { ApiError, callApi } from "@/lib/client";

/**
 * Picking a username: the step the app shows a new account
 * (/welcome/username). Claimed through the API, which also starts the
 * profile, so the player can be found and followed.
 */
export function UsernameStep({ user, onDone }: { user: User; onDone: () => void }) {
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const handle = normalizeUsername(name);

  async function submit(e: FormEvent) {
    e.preventDefault();
    const problem = usernameProblem(name);
    if (problem) return setError(problem);
    setBusy(true);
    setError("");
    try {
      await callApi(user, "/v1/me/username", { method: "POST", body: { username: handle } });
      onDone();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Something went wrong. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="card username-step" onSubmit={submit}>
      <h2 className="card-title">Pick your username</h2>
      <p className="muted small">It&apos;s how teammates find you. You can&apos;t change it later.</p>
      <div className="username-row">
        <span aria-hidden="true">@</span>
        <label className="visually-hidden" htmlFor="username">
          Username
        </label>
        <input
          id="username"
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoComplete="username"
          autoCapitalize="none"
          spellCheck={false}
          maxLength={30}
          placeholder="pat.lee"
        />
        <button className="btn btn-primary btn-small" type="submit" disabled={busy || !handle}>
          Save
        </button>
      </div>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </form>
  );
}
