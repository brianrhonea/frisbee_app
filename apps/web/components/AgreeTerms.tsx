"use client";
// Read and agree to the Community Guidelines and Terms of Service, before
// anything else (agreements.ts in packages/shared; AgreeTermsScreen in the
// app). New accounts see it during sign-up; existing members once, on
// their next visit, and again when termsVersion goes up.
import { type AgreementStatus, agreementPath, agreementPoints, termsVersion } from "@stall10/shared";
import type { User } from "firebase/auth";
import { signOut } from "firebase/auth";
import Link from "next/link";
import { useState } from "react";
import { callApi, problem } from "@/lib/client";
import { firebaseAuth } from "@/lib/firebase";

export function AgreeTerms({ user, onDone }: { user: User; onDone: () => void }) {
  const [checked, setChecked] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function agree() {
    setBusy(true);
    setError("");
    try {
      await callApi<AgreementStatus>(user, agreementPath, { method: "PUT", body: { version: termsVersion } });
      onDone();
    } catch (e) {
      setError(problem(e));
      setBusy(false);
    }
  }

  return (
    <div className="page">
      <div className="auth-card auth-card-wide agree-terms">
        <header className="auth-head">
          <h1>Before you start</h1>
          <p>Stall 10 is for players, teams and families. Everyone agrees to keep it that way.</p>
        </header>
        <ul className="agree-points">
          {agreementPoints.map((p) => (
            <li key={p}>{p}</li>
          ))}
        </ul>
        <p className="agree-links">
          Read the{" "}
          <Link href="/guidelines" target="_blank">
            Community Guidelines
          </Link>
          ,{" "}
          <Link href="/terms" target="_blank">
            Terms of Service
          </Link>{" "}
          and{" "}
          <Link href="/privacy" target="_blank">
            Privacy Policy
          </Link>
          .
        </p>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (checked) void agree();
          }}
        >
          <label className="agree-check">
            <input type="checkbox" checked={checked} disabled={busy} onChange={(e) => setChecked(e.target.checked)} />
            <span>I&apos;ve read and agree to the Community Guidelines and Terms of Service</span>
          </label>
          {error && <small className="form-error">{error}</small>}
          <button type="submit" className="btn btn-primary" disabled={!checked || busy}>
            {busy ? "Saving…" : "Continue"}
          </button>
          <button type="button" className="link-button small" disabled={busy} onClick={() => void signOut(firebaseAuth()!)}>
            Sign out
          </button>
        </form>
      </div>
    </div>
  );
}
