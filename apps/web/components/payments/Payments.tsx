"use client";
// Online payments for tournament fees (packages/shared/src/payments.ts):
// the host owner's payout card, and the Pay button for a team's bid or
// spot fee or a player's own entry fee. Both show nothing until the API
// says online payments are available. Stripe's pages open in this tab
// and send people back to /payments/*.
import {
  centsLabel,
  chargeCoveringFees,
  type CheckoutResult,
  feeBreakdown,
  onlinePaymentProblem,
  type PaymentFees,
  type PayOptions,
  type PayoutAccountView,
  type PayoutLinkResult,
  paymentNoteMax,
  paymentPaths,
  platformFeeLabel,
} from "@stall10/shared";
import type { User } from "firebase/auth";
import { useCallback, useEffect, useState } from "react";
import type { PaymentDoc } from "@/components/drafts/data";
import { callApi, problem } from "@/lib/client";

/** Reloads [load] when the tab comes back into view (back from Stripe in another tab). */
function useOnVisible(load: () => void) {
  useEffect(() => {
    const onVisible = () => document.visibilityState === "visible" && load();
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, [load]);
}

/** A per-tab note that Pay was pressed (sessionStorage, which survives Stripe's redirect); off when storage is blocked. */
function readFlag(key: string): boolean {
  try {
    return sessionStorage.getItem(key) === "1";
  } catch {
    return false;
  }
}
function setFlag(key: string, on: boolean) {
  try {
    if (on) sessionStorage.setItem(key, "1");
    else sessionStorage.removeItem(key);
  } catch {
    // Storage blocked: the page just doesn't wait for the check.
  }
}

/** Opens a Stripe link for [path] in this tab. */
export async function goToStripe(user: User, path: string, body: unknown): Promise<void> {
  const { url } = await callApi<CheckoutResult | PayoutLinkResult>(user, path, { method: "POST", body });
  if (!url.startsWith("https://")) throw new Error("Stripe sent back no page.");
  window.location.assign(url);
}

/** The host owner's "Take payments online" card; [amountCents] is the event's fee, for the "you get about…" line ($100 without one). */
export function PayoutsCard({ user, teamId, amountCents, payerCovers = false }: { user: User; teamId: string; amountCents?: number; payerCovers?: boolean }) {
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
      <FeeBreakdownNote user={user} amountCents={amountCents ?? 10_000} currency="USD" compact payerCovers={payerCovers} />
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
  const [checking, setChecking] = useState(false);
  const [checkFailed, setCheckFailed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const payingKey = `stall10.paying.${tournamentId}.${teamId ?? "me"}`;
  // Each load asks Stripe about the last checkout, so coming back shows it
  // paid without waiting for the webhook. Back from paying (marked when Pay
  // was pressed), the button waits for that answer.
  const load = useCallback(() => {
    const q = teamId ? `?team=${encodeURIComponent(teamId)}` : "";
    const returning = readFlag(payingKey);
    setChecking(returning);
    callApi<PayOptions>(user, `${paymentPaths.payOptions(encodeURIComponent(tournamentId))}${q}`)
      .then(
        (o) => {
          setOptions(o);
          setCheckFailed(false);
          setFlag(payingKey, false);
        },
        () => {
          if (returning) setCheckFailed(true);
          else setOptions(null);
        },
      )
      .finally(() => setChecking(false));
  }, [user, tournamentId, teamId, payingKey]);
  useEffect(load, [load]);
  useOnVisible(load);
  if (checking && !options) return <small className="muted" aria-busy="true">Checking your payment…</small>;
  if (checkFailed) {
    return (
      <div className="pay-online">
        <small className="muted">Couldn&apos;t check your payment. If you paid, it shows here once Stripe confirms it.</small>
        <button type="button" className="btn btn-small" onClick={load}>
          Check again
        </button>
      </div>
    );
  }
  if (!options || options.amountCents <= 0) return null;
  const body = teamId ? { payer: "team", teamId } : { payer: "player" };
  const payOffline = async (offline: boolean) => {
    setBusy(true);
    setError("");
    try {
      await callApi(user, paymentPaths.offline(encodeURIComponent(tournamentId)), { method: "PUT", body: { ...body, offline } });
      load();
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(false);
    }
  };
  const offline =
    !options.paid && options.pending !== "processing" ? (
      options.offlineAt ? (
        <small className="muted">
          You told the host you&apos;ll pay another way. Ask them to mark it paid when it arrives.{" "}
          <button type="button" className="text-btn" disabled={busy} onClick={() => payOffline(false)}>
            Undo
          </button>
        </small>
      ) : (
        <>
          <button type="button" className="text-btn" disabled={busy} onClick={() => payOffline(true)}>
            We&apos;ll pay another way
          </button>
          <small className="muted">By check, purchase order or however the host takes it. If the host hasn&apos;t said how, ask them.</small>
        </>
      )
    ) : null;
  const pay = async () => {
    setBusy(true);
    setError("");
    try {
      setFlag(payingKey, true);
      await goToStripe(user, paymentPaths.checkout(encodeURIComponent(tournamentId)), body);
    } catch (e) {
      setError(problem(e));
      setBusy(false);
    }
  };
  return (
    <div className="pay-online">
      {withStatus && <small className="muted">{options.paid ? `Fee ${centsLabel(options.amountCents)} paid.` : `Fee ${centsLabel(options.amountCents)} to pay.`}</small>}
      {checking ? (
        <small className="muted" aria-busy="true">
          Checking your payment…
        </small>
      ) : options.pending === "processing" && !options.paid ? (
        <small className="muted">{options.reason}</small>
      ) : (
        options.online && (
          <>
            <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={pay}>
              {busy ? "Opening checkout…" : `Pay ${centsLabel(options.chargeCents)} online`}
            </button>
            <small className="muted">
              {options.processingCents > 0 ? `Includes a ${centsLabel(options.processingCents)} processing fee. ` : ""}
              Secure checkout by Stripe. It shows as paid here once Stripe confirms it.
            </small>
          </>
        )
      )}
      {!checking && offline}
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}

/**
 * What reaches the host of [amountCents] paid online: the host form's note
 * under the price, and (with [compact]) the payout card's example. Mirrors
 * feeNote in apps/mobile/lib/ui/payments/widgets/payment_widgets.dart.
 */
export function feeNote(fees: PaymentFees, amountCents: number, currency: string, compact = false, payerCovers = false): string | null {
  if (!fees.available || amountCents <= 0) return null;
  const charge = payerCovers ? chargeCoveringFees(amountCents, fees.platform, fees.card) : amountCents;
  const why = onlinePaymentProblem(charge, currency, fees.platform);
  if (why) return compact ? null : why;
  if (payerCovers && compact) return `On a ${centsLabel(amountCents)} fee, payers pay ${centsLabel(charge)} online and you get the whole ${centsLabel(amountCents)}.`;
  if (payerCovers) {
    const [total, fee, extra] = [charge, amountCents, charge - amountCents].map(centsLabel);
    return `Paid online, they pay ${total} (${fee} plus a ${extra} processing fee) and you get the whole ${fee}. Paid your own way, they pay ${fee}.`;
  }
  const b = feeBreakdown(amountCents, fees.platform, fees.card);
  const [amount, host, ours, stripe] = [b.amountCents, b.hostCents, b.platformCents, b.stripeCents].map(centsLabel);
  if (compact) return `On a ${amount} fee you get about ${host}: Stall 10 keeps ${ours} and Stripe about ${stripe}.`;
  return (
    `Paid online in Stall 10, you get about ${host} of each ${amount}. ` +
    `Stall 10 keeps ${ours} (${platformFeeLabel(fees.platform)}) and Stripe about ${stripe} (${platformFeeLabel(fees.card)}, its usual card fee). ` +
    "Paid your own way, you keep it all."
  );
}

/** The fees on a payment made online; null until the API answers (or when it can't). */
export function usePaymentFees(user: User | null | undefined): PaymentFees | null {
  const [fees, setFees] = useState<PaymentFees | null>(null);
  useEffect(() => {
    if (!user) return;
    let live = true;
    callApi<PaymentFees>(user, paymentPaths.fees).then(
      (f) => live && setFees(f),
      () => live && setFees(null),
    );
    return () => {
      live = false;
    };
  }, [user]);
  return fees;
}

/** [feeNote] for a price a host is setting; nothing while online payments are off. */
export function FeeBreakdownNote({
  user,
  amountCents,
  currency,
  compact = false,
  payerCovers = false,
}: {
  user: User | null | undefined;
  amountCents: number | null;
  currency: string;
  compact?: boolean;
  payerCovers?: boolean;
}) {
  const fees = usePaymentFees(user);
  const note = fees && amountCents != null ? feeNote(fees, amountCents, currency, compact, payerCovers) : null;
  if (!note) return null;
  return compact ? <p className="fee-note">{note}</p> : <small className="muted fee-note">{note}</small>;
}

/** "Paid", "Paying another way", "Overdue" or "Unpaid": a fee's state on the host's lists (paymentStatusLabel in the app). */
export function paymentStatusLabel(p: PaymentDoc | undefined, overdue: boolean): string {
  if (p?.paid === true) return "Paid";
  if (p?.offlineAt) return "Paying another way";
  return overdue ? "Overdue" : "Unpaid";
}

/**
 * The host's controls for one payer's fee: paid or not (shown at once,
 * undone if the save fails), the state, and a note ("Check #1042"). Saves
 * through the API, which keeps the payment history.
 */
export function HostPaymentControls({ user, tournamentId, payerId, payment, overdue }: { user: User; tournamentId: string; payerId: string; payment: PaymentDoc | undefined; overdue: boolean }) {
  const [shown, setShown] = useState<{ paid: boolean; note: string } | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const [error, setError] = useState("");
  const live = { paid: payment?.paid === true, note: payment?.note ?? "" };
  const now = shown ?? live;
  // The live record takes over once it agrees.
  useEffect(() => {
    if (shown && shown.paid === live.paid && shown.note === live.note) setShown(null);
  }, [shown, live.paid, live.note]);
  const save = async (next: { paid: boolean; note: string }) => {
    setShown(next);
    setError("");
    try {
      await callApi(user, paymentPaths.mark(encodeURIComponent(tournamentId), encodeURIComponent(payerId)), { method: "PUT", body: next });
    } catch (e) {
      setShown(null);
      setError(problem(e));
    }
  };
  const label = paymentStatusLabel({ ...payment, paid: now.paid }, overdue);
  return (
    <span className="host-payment">
      <label className="check-row small">
        <input type="checkbox" checked={now.paid} onChange={(e) => void save({ ...now, paid: e.target.checked })} />
        {label}
      </label>
      {editing === null ? (
        <button type="button" className="text-btn" onClick={() => setEditing(now.note)} title={now.note ? `Payment note: ${now.note}` : "Add a payment note"}>
          {now.note ? now.note : "Add note"}
        </button>
      ) : (
        <form
          className="host-payment-note"
          onSubmit={(e) => {
            e.preventDefault();
            const note = editing.trim();
            setEditing(null);
            if (note !== now.note) void save({ ...now, note });
          }}
        >
          <input autoFocus maxLength={paymentNoteMax} placeholder="e.g. Check #1042" value={editing} onChange={(e) => setEditing(e.target.value)} aria-label="Payment note" />
          <button type="submit" className="btn btn-small">
            Save
          </button>
          <button type="button" className="text-btn" onClick={() => setEditing(null)}>
            Cancel
          </button>
        </form>
      )}
      {error && <small className="form-error">{error}</small>}
    </span>
  );
}
