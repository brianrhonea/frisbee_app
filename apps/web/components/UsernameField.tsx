"use client";
import { normalizeUsername, usernameLimits, usernameProblem } from "@stall10/shared";
import { FirebaseError } from "firebase/app";
import { doc, getDoc } from "firebase/firestore";
import { useEffect, useState } from "react";
import { firestoreDb } from "@/lib/firebase";

/** Where a typed username stands (the app's UsernameStatus). */
export type UsernameStatus = "empty" | "invalid" | "checking" | "available" | "taken" | "failed";

/**
 * Whether [handle] is free: usernames/{name} doesn't exist. Signed out,
 * the rules refuse a name somebody has, which means it's taken. Signed in,
 * a name the caller already holds counts as free for them.
 */
async function available(handle: string, uid: string | null): Promise<boolean> {
  const db = firestoreDb();
  if (!db) throw new Error("No database");
  try {
    const snap = await getDoc(doc(db, "usernames", handle));
    return !snap.exists() || (uid != null && snap.data()?.uid === uid);
  } catch (e) {
    if (e instanceof FirebaseError && e.code === "permission-denied" && uid == null) return false;
    throw e;
  }
}

/**
 * "pat.lee" from "Pat Lee": a starting suggestion they can change, or ""
 * when the name makes no valid one (the app's ChooseUsernameViewModel).
 */
export function suggestUsername(name: string | null | undefined): string {
  const n = (name ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/^\.+|\.+$/g, "");
  const s = n.length > usernameLimits.max ? n.slice(0, usernameLimits.max).replace(/\.+$/, "") : n;
  return usernameProblem(s) == null ? s : "";
}

/** The status of [value] as it's typed: its format at once, whether it's free after a pause. */
export function useUsernameCheck(value: string, uid: string | null, delay = 400) {
  const handle = normalizeUsername(value);
  const problem = handle ? usernameProblem(handle) : null;
  const [result, setResult] = useState<{ handle: string; status: UsernameStatus } | null>(null);

  useEffect(() => {
    if (!handle || problem) return;
    let live = true;
    const t = setTimeout(() => {
      available(handle, uid)
        .then((free) => live && setResult({ handle, status: free ? "available" : "taken" }))
        .catch(() => live && setResult({ handle, status: "failed" }));
    }, delay);
    return () => {
      live = false;
      clearTimeout(t);
    };
  }, [handle, problem, uid, delay]);

  const status: UsernameStatus = !handle
    ? "empty"
    : problem
      ? "invalid"
      : result?.handle === handle
        ? result.status
        : "checking";
  const message =
    status === "invalid"
      ? problem
      : status === "available"
        ? `@${handle} is available`
        : status === "taken"
          ? `@${handle} is taken. Try another.`
          : status === "failed"
            ? "Couldn't check that username. Try again."
            : null;
  return { handle, status, message, markTaken: () => setResult({ handle, status: "taken" }) };
}

/** The username input: an "@" in front, and what the check says under it. */
export function UsernameField({
  value,
  onChange,
  check,
  inputId,
  hint = "How teammates find and mention you. You can't change it later.",
}: {
  inputId?: string;
  value: string;
  onChange: (v: string) => void;
  check: ReturnType<typeof useUsernameCheck>;
  hint?: string;
}) {
  const tone = check.status === "available" ? "ok" : check.status === "checking" || check.status === "empty" ? "" : "bad";
  return (
    <label className="username-field">
      Username
      <span className={`username-input ${tone}`}>
        <span aria-hidden="true">@</span>
        <input
          id={inputId}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          autoComplete="username"
          autoCapitalize="none"
          spellCheck={false}
          maxLength={usernameLimits.max + 1}
          placeholder="pat.lee"
          aria-invalid={tone === "bad" ? true : undefined}
          aria-describedby="username-note"
        />
        {check.status === "checking" && <span className="username-spin" aria-hidden="true" />}
      </span>
      <small id="username-note" className={tone === "ok" ? "form-ok" : tone === "bad" ? "form-error" : "muted"} aria-live="polite">
        {check.message ?? hint}
      </small>
    </label>
  );
}
