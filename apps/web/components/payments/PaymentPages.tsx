"use client";
import { paymentPaths } from "@stall10/shared";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { useAuth } from "@/components/AuthProvider";
import { problem } from "@/lib/client";
import { goToStripe, PayoutsCard } from "./Payments";

const validId = (v: string | null): v is string => !!v && /^[A-Za-z0-9_-]{1,128}$/.test(v);

/**
 * Back from Stripe's onboarding: where the account stands. With `retry`
 * (Stripe's link expired before it was finished) it asks for a fresh link
 * and goes straight back.
 */
export function PayoutsReturn() {
  const { user } = useAuth();
  const params = useSearchParams();
  const teamId = params.get("team");
  const retry = params.get("retry") === "1";
  const [error, setError] = useState("");
  const started = useRef(false);
  useEffect(() => {
    if (!user || !retry || !validId(teamId) || started.current) return;
    started.current = true;
    goToStripe(user, paymentPaths.payoutLink(encodeURIComponent(teamId)), {}).catch((e) => setError(problem(e)));
  }, [user, retry, teamId]);
  if (!user) return null;
  if (!validId(teamId)) return <p className="muted">This link is missing its team.</p>;
  if (retry && !error) return <p className="muted" aria-busy="true">Opening Stripe…</p>;
  return (
    <div className="stack">
      {error && <p className="form-error">{error}</p>}
      <PayoutsCard user={user} teamId={teamId} />
      <p>
        <Link href={`/teams/${encodeURIComponent(teamId)}`}>Back to the team</Link>
      </p>
    </div>
  );
}

/** After paying: Stripe confirms it in a moment, then it shows as paid. */
export function PaymentDone() {
  const params = useSearchParams();
  const tournamentId = params.get("tournament");
  return (
    <section className="card stack">
      <p>Thanks! Stripe will email you a receipt. The fee shows as paid on the event once Stripe confirms it, usually within a minute.</p>
      <p className="muted">Paying in the Stall 10 app? You can go back to it now.</p>
      {validId(tournamentId) && (
        <p>
          <Link className="btn btn-primary btn-small" href={`/tournaments/${encodeURIComponent(tournamentId)}`}>
            Back to the event
          </Link>
        </p>
      )}
    </section>
  );
}
