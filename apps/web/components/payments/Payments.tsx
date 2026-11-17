"use client";
// Online payments for tournament fees (packages/shared/src/payments.ts):
// the host owner's payout card, and the Pay button for a team's bid or
// spot fee or a player's own entry fee. Both show nothing until the API
// says online payments are available. Stripe's pages open in this tab
// and send people back to /payments/*.
import { centsLabel, type CheckoutResult, type PayOptions, type PayoutAccountView, type PayoutLinkResult, paymentPaths } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useCallback, useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";

/** Reloads [load] when the tab comes back into view (back from Stripe in another tab). */
function useOnVisible(load: () => void) {
  useEffect(() => {
    const onVisible = () => document.visibilityState === "visible" && load();
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, [load]);
}

/** Opens a Stripe link for [path] in this tab. */
export async function goToStripe(user: User, path: string, body: unknown): Promise<void> {
  const { url } = await callApi<CheckoutResult | PayoutLinkResult>(user, path, { method: "POST", body });
  if (!url.startsWith("https://")) throw new Error("Stripe sent back no page.");
  window.location.assign(url);
}

/** The host owner's "Take payments online" card. */
export function PayoutsCard({ user, teamId }: { user: User; teamId: string }) {
  const [account, setAccount] = useState<PayoutAccountView | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const load = useCallback(() => {
    callApi<PayoutAccountView>(user, paymentPaths.payouts(encodeURIComponent(teamId))).then(setAccount, () => setAccount(null));
  }, [user, teamId]);
  useEffect(load, [load]);
  useOnVisible(load);
  if (!account?.available) return null;
  const connect = async () => {
    setBusy(true);
    setError("");
    try {
      await goToStripe(user, paymentPaths.payoutLink(encodeURIComponent(teamId)), {});
    } catch (e) {
      setError(problem(e));
      setBusy(false);
    }
  };
  const copy = {
    none: {
      title: "Take payments online",
      body: `Let teams and players pay their fees in Stall 10 instead of collecting them yourself. Payments go to your own Stripe account. Stripe keeps its card fee and Stall 10 keeps ${account.feeLabel} of each payment.`,
      action: "Set up with Stripe",
    },
    pending: { title: "Finish setting up payments", body: "Stripe still needs a few details before you can take payments.", action: "Continue with Stripe" },
    ready: {
      title: "Online payments are on",
      body: `Teams and players can pay their fees in Stall 10. Refunds and payouts are in your Stripe Dashboard. Stall 10 keeps ${account.feeLabel} of each payment.`,
      action: null,
    },
  }[account.status];
  return (
    <section className="card payouts-card">
      <h2 className="card-title">{copy.title}</h2>
      <p>{copy.body}</p>
      {error && <p className="form-error">{error}</p>}
      {copy.action && (
        <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={connect}>
          {busy ? "Opening Stripe…" : copy.action}
        </button>
      )}
    </section>
  );
}

/**
 * The fee's state for [teamId] (or the user's own entry fee without one),
 * and a Pay button when the host takes payments through Stall 10.
 * [withStatus] also says whether it's paid (the team card has no other
 * line for it).
 */
export function PayOnline({ user, tournamentId, teamId, withStatus = false }: { user: User; tournamentId: string; teamId?: string; withStatus?: boolean }) {
  const [options, setOptions] = useState<PayOptions | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const load = useCallback(() => {
    const q = teamId ? `?team=${encodeURIComponent(teamId)}` : "";
    callApi<PayOptions>(user, `${paymentPaths.payOptions(encodeURIComponent(tournamentId))}${q}`).then(setOptions, () => setOptions(null));
  }, [user, tournamentId, teamId]);
  useEffect(load, [load]);
  useOnVisible(load);
  if (!options || options.amountCents <= 0) return null;
  const pay = async () => {
    setBusy(true);
    setError("");
    try {
      await goToStripe(user, paymentPaths.checkout(encodeURIComponent(tournamentId)), teamId ? { payer: "team", teamId } : { payer: "player" });
    } catch (e) {
      setError(problem(e));
      setBusy(false);
    }
  };
  return (
    <div className="pay-online">
      {withStatus && <small className="muted">{options.paid ? `Fee ${centsLabel(options.amountCents)} paid.` : `Fee ${centsLabel(options.amountCents)} to pay.`}</small>}
      {options.online && (
        <>
          <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={pay}>
            {busy ? "Opening checkout…" : `Pay ${centsLabel(options.amountCents)} online`}
          </button>
          <small className="muted">Secure checkout by Stripe. It shows as paid here once Stripe confirms it.</small>
        </>
      )}
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}
