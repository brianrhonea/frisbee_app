"use client";
// Online payments for tournament fees (packages/shared/src/payments.ts):
// the host's payouts card (with what it has been paid), the Pay button
// for a team's bid or spot fee or a player's own entry fee, and the
// organizers' Refund. Stall 10 takes each payment and sends the host its
// fee once the event is over. Everything shows nothing until the API says
// online payments are available. With a publishable key
// (NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY), Checkout and the payout setup
// open inside this page (Stripe's embedded components); without one,
// Stripe's pages open in this tab and send people back to /payments/*.
import {
  centsLabel,
  type CheckoutResult,
  type EarningsView,
  onlineCharge,
  onlinePaymentProblem,
  type PaymentFees,
  type PayOptions,
  type PayoutAccountView,
  type PayoutLinkResult,
  type PayoutSessionResult,
  payoutStatusLabels,
  paidOnlineNote,
  paymentNoteMax,
  paymentPaths,
  payoutReviewNote,
  payoutsReauthMessage,
  payoutsSetupNote,
  payoutTimingNote,
  platformFeeLabel,
  refundPolicyNote,
} from "@stall10/shared";
import type { StripeEmbeddedCheckout } from "@stripe/stripe-js";
import type { User } from "firebase/auth";
import { useCallback, useEffect, useRef, useState } from "react";
import type { PaymentDoc } from "@/components/drafts/data";
import { callApi, problem } from "@/lib/client";
import { ConfirmSignIn } from "./ConfirmSignIn";
import { StatusPill } from "../ui/StatusPill";

/** One fee's state on the host's payouts card (EarningsStatus.label in the app). */
const earningsStatusLabels: Record<EarningsView["items"][number]["status"], string> = {
  held: "Held until the event is over",
  sent: "Sent",
  kept: "Stall 10 event",
  refunded: "Refunded",
  disputed: "Disputed",
};

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
  if (!url?.startsWith("https://")) throw new Error("Stripe sent back no page.");
  window.location.assign(url);
}

/** Stripe's publishable key: Checkout in this page with one, Stripe's page without. */
const publishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? "";

/**
 * Stripe's Checkout inside this page, for the session [clientSecret] on
 * Stall 10's account ([account] null; a host's for a session made before
 * Stall 10 collected). Paying sends the payer on to /payments/done, as
 * Stripe's own page does; [onClose] puts the Pay button back.
 */
function EmbeddedPay({ clientSecret, account, onClose }: { clientSecret: string; account: string | null; onClose: () => void }) {
  const box = useRef<HTMLDivElement>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    let live = true;
    let checkout: StripeEmbeddedCheckout | null = null;
    (async () => {
      try {
        const { loadStripe } = await import("@stripe/stripe-js");
        const stripe = await loadStripe(publishableKey, account ? { stripeAccount: account } : undefined);
        if (!stripe) throw new Error("Stripe didn't load.");
        const made = await stripe.createEmbeddedCheckoutPage({ clientSecret });
        if (!live) return made.destroy();
        checkout = made;
        if (box.current) made.mount(box.current);
      } catch {
        if (live) setError("Couldn't open the checkout. Check your connection and try again.");
      }
    })();
    return () => {
      live = false;
      checkout?.destroy();
    };
  }, [clientSecret, account]);
  return (
    <div className="embedded-pay">
      <div className="embedded-pay-head">
        <strong>Pay securely with Stripe</strong>
        <button type="button" className="text-btn" onClick={onClose}>
          Cancel
        </button>
      </div>
      {error ? <p className="form-error">{error}</p> : <div ref={box} className="embedded-pay-frame" aria-busy="true" />}
    </div>
  );
}

/**
 * Stripe's own forms inside this page (Connect embedded components), on a
 * session from POST /v1/teams/:teamId/payouts/session, or from
 * [clientSecret] when the app's WebView hands one over (/embed/payouts).
 * [view] "setup": linking the payout account ([onExit] runs when the
 * person finishes or closes it); "manage": what Stripe needs, the bank
 * account, and payouts.
 */
export function EmbeddedOnboarding({
  user,
  teamId,
  clientSecret,
  onExit,
  view = "setup",
}: {
  user?: User;
  teamId?: string;
  clientSecret?: string;
  onExit: () => void;
  view?: "setup" | "manage";
}) {
  const box = useRef<HTMLDivElement>(null);
  const exit = useRef(onExit);
  exit.current = onExit;
  const [error, setError] = useState("");
  // The API wants a sign-in from the last 15 minutes first (ConfirmSignIn).
  const [reauth, setReauth] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let live = true;
    let elements: HTMLElement[] = [];
    (async () => {
      try {
        if (!publishableKey) throw new Error("no key");
        const session = async () => {
          if (clientSecret) return clientSecret;
          if (!user || !teamId) throw new Error("no session");
          const r = await callApi<PayoutSessionResult>(user, paymentPaths.payoutSession(encodeURIComponent(teamId)), { method: "POST", body: {} });
          return r.clientSecret;
        };
        // Asked for here, before Stripe's form loads, so a refusal shows our
        // message (Stripe's form would only say it couldn't sign in).
        let first: string | null;
        try {
          first = await session();
        } catch (e) {
          if (live && e instanceof Error && e.message === payoutsReauthMessage && user) return setReauth(true);
          throw e;
        }
        const { loadConnectAndInitialize } = await import("@stripe/connect-js");
        // Stripe asks again when the session runs out.
        const fetchClientSecret = async () => {
          const s = first ?? (await session());
          first = null;
          return s;
        };
        const connect = loadConnectAndInitialize({
          publishableKey,
          fetchClientSecret,
          appearance: { variables: { colorPrimary: "#4338CA", fontFamily: "inherit", borderRadius: "10px" } },
        });
        if (view === "manage") {
          elements = [connect.create("notification-banner"), connect.create("account-management"), connect.create("payouts")];
        } else {
          const onboarding = connect.create("account-onboarding");
          onboarding.setOnExit(() => exit.current());
          elements = [onboarding];
        }
        if (!live) return;
        for (const e of elements) box.current?.appendChild(e);
      } catch (e) {
        if (live) setError("Couldn't open Stripe's setup here. Check your connection and try again.");
      }
    })();
    return () => {
      live = false;
      for (const e of elements) e.remove();
    };
  }, [user, teamId, clientSecret, view, attempt]);
  if (reauth && user) {
    return (
      <ConfirmSignIn
        user={user}
        onConfirmed={() => {
          setReauth(false);
          setAttempt((n) => n + 1);
        }}
      />
    );
  }
  return error ? <p className="form-error">{error}</p> : <div ref={box} className="embedded-onboarding" aria-busy="true" />;
}

/**
 * "Payments: On / Finish setup / Not set up" for a host, with setup right
 * here (Stripe's form in the page; Stripe's own page only without a
 * publishable key). The host's owner sets it up; other managers see the
 * status and who to ask. [amountCents] is the event's fee, for the
 * "payers pay…" line ($100 without one).
 */
export function PayoutsCard({ user, teamId, amountCents }: { user: User; teamId: string; amountCents?: number }) {
  const [account, setAccount] = useState<PayoutAccountView | null>(null);
  const [earnings, setEarnings] = useState<EarningsView | null>(null);
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState<"setup" | "manage" | null>(null);
  const [error, setError] = useState("");
  const load = useCallback(() => {
    const id = encodeURIComponent(teamId);
    callApi<PayoutAccountView>(user, paymentPaths.payouts(id)).then(
      (a) => {
        setAccount(a);
        // What it has been paid, once payouts are linked; the card shows without it.
        if (a.available && a.status !== "none") callApi<EarningsView>(user, paymentPaths.earnings(id)).then(setEarnings, () => setEarnings(null));
        else setEarnings(null);
      },
      () => setAccount(null),
    );
  }, [user, teamId]);
  useEffect(load, [load]);
  useOnVisible(load);
  if (!account?.available) return null;
  const connect = async () => {
    if (publishableKey) {
      setOpen("setup");
      return;
    }
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
      body: `Let teams and players pay their fees in Stall 10 instead of collecting them yourself. Stall 10 takes the payments and sends you the whole fee a few days after each event: payers also pay Stall 10's ${account.feeLabel} and Stripe's card fee. Add your bank details here; you don't need a Stripe account.`,
      action: "Set up payouts",
    },
    pending: { title: "Finish setting up payments", body: "Stripe needs a few more details before Stall 10 can send you your fees.", action: "Finish setup" },
    ready: {
      title: "Online payments are on",
      body: `Teams and players pay their fees in Stall 10, and Stall 10 sends you the whole fee a few days after each event. ${payoutReviewNote} Refund a team from the event's Teams tab. Payers also pay Stall 10's ${account.feeLabel} and Stripe's card fee.`,
      action: null,
    },
  }[account.status];
  const e = earnings;
  const hasEarnings = !!e && (e.items.length > 0 || e.owedCents > 0);
  return (
    <section className="card payouts-card">
      <div className="card-head">
        <h2 className="card-title">{copy.title}</h2>
        <StatusPill tone={account.status === "ready" ? "success" : "attention"}>Payments: {payoutStatusLabels[account.status].label}</StatusPill>
      </div>
      <p>{copy.body}</p>
      <FeeBreakdownNote user={user} amountCents={amountCents ?? 10_000} currency="USD" compact />
      {hasEarnings && (
        <>
          <p className="payout-totals">
            {[
              `Held ${centsLabel(e.heldCents)}`,
              `Sent ${centsLabel(e.sentCents)}`,
              ...(e.refundedCents > 0 ? [`Refunded ${centsLabel(e.refundedCents)}`] : []),
              ...(e.disputedCents > 0 ? [`Disputed ${centsLabel(e.disputedCents)}`] : []),
            ].join(" · ")}
          </p>
          {e.owedCents > 0 && <p className="muted small">{centsLabel(e.owedCents)} taken back after a refund or dispute comes off your next payout.</p>}
          {e.items.length > 0 && (
            <details className="payout-items">
              <summary>Each fee ({e.items.length})</summary>
              <ul>
                {e.items.map((i, n) => (
                  <li key={`${i.tournamentId}-${n}`}>
                    <span>{i.label}</span>
                    <span className="num">{centsLabel(i.amountCents)}</span>
                    <span className="muted small">
                      {earningsStatusLabels[i.status]}
                      {i.at ? ` · ${new Date(i.at).toLocaleDateString(undefined, { month: "short", day: "numeric" })}` : ""}
                    </span>
                  </li>
                ))}
              </ul>
            </details>
          )}
        </>
      )}
      {error && <p className="form-error">{error}</p>}
      {copy.action && !account.canSetUp && <p className="muted small">Only {account.ownerName} can set up payments. Ask them to open this page.</p>}
      {copy.action && account.canSetUp && !open && (
        <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={connect}>
          {busy ? "Opening…" : copy.action}
        </button>
      )}
      {!copy.action && account.canSetUp && publishableKey && !open && (
        <button type="button" className="btn btn-small" onClick={() => setOpen("manage")}>
          Bank account and payouts
        </button>
      )}
      {open && (
        <div className="embedded-pay">
          <div className="embedded-pay-head">
            <strong>{open === "manage" ? "Bank account and payouts" : "Set up payouts"}</strong>
            <button
              type="button"
              className="text-btn"
              onClick={() => {
                setOpen(null);
                load();
              }}
            >
              Close
            </button>
          </div>
          {open === "setup" && <p className="muted small">{payoutsSetupNote}</p>}
          <EmbeddedOnboarding
            user={user}
            teamId={teamId}
            view={open}
            onExit={() => {
              setOpen(null);
              load();
            }}
          />
        </div>
      )}
    </section>
  );
}

/** "Payments: On" for a team page or settings, for its managers; nothing when online payments are off. */
export function PayoutsStatus({ user, teamId, href }: { user: User; teamId: string; href: string }) {
  const [account, setAccount] = useState<PayoutAccountView | null>(null);
  useEffect(() => {
    callApi<PayoutAccountView>(user, paymentPaths.payouts(encodeURIComponent(teamId))).then(setAccount, () => setAccount(null));
  }, [user, teamId]);
  if (!account?.available) return null;
  return (
    <a className={`pill payouts-status payouts-${account.status}`} href={href}>
      Payments: {payoutStatusLabels[account.status].label}
    </a>
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
  /** The embedded Checkout open in this page. */
  const [embedded, setEmbedded] = useState<{ clientSecret: string; account: string | null } | null>(null);
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
      const path = paymentPaths.checkout(encodeURIComponent(tournamentId));
      if (!publishableKey) {
        await goToStripe(user, path, body);
        return;
      }
      const r = await callApi<CheckoutResult>(user, path, { method: "POST", body: { ...body, ui: "embedded" } });
      if (!r.clientSecret) throw new Error("Stripe sent back no checkout.");
      setEmbedded({ clientSecret: r.clientSecret, account: r.account });
      setBusy(false);
    } catch (e) {
      setFlag(payingKey, false);
      setError(problem(e));
      setBusy(false);
    }
  };
  if (embedded) {
    return (
      <div className="pay-online">
        <EmbeddedPay
          clientSecret={embedded.clientSecret}
          account={embedded.account}
          onClose={() => {
            setEmbedded(null);
            setFlag(payingKey, false);
            load();
          }}
        />
      </div>
    );
  }
  return (
    <div className="pay-online">
      {withStatus && <small className="muted">{options.paid ? `Fee ${centsLabel(options.amountCents)} paid.` : `Fee ${centsLabel(options.amountCents)} to pay.`}</small>}
      {checking ? (
        <small className="muted" aria-busy="true">
          Checking your payment…
        </small>
      ) : options.pending === "processing" && !options.paid ? (
        <small className="muted">{options.reason}</small>
      ) : !options.online ? (
        // Why it can't be paid online here (the host isn't set up, it's your
        // own event, …), so the other ways below make sense.
        !options.paid && options.amountCents > 0 && options.reason && <small className="muted">{options.reason}</small>
      ) : (
        options.online && (
          <>
            <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={pay}>
              {busy ? "Opening checkout…" : `Pay ${centsLabel(options.chargeCents)} online`}
            </button>
            <small className="muted">
              {options.processingCents > 0 ? `Includes ${centsLabel(options.processingCents)} in service and processing fees. ` : ""}
              Secure checkout by Stripe. It shows as paid here once Stripe confirms it. {payoutTimingNote} {refundPolicyNote}
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
export function feeNote(fees: PaymentFees, amountCents: number, currency: string, compact = false): string | null {
  if (!fees.available || amountCents <= 0) return null;
  const c = onlineCharge({ amountCents }, fees.platform, fees.card);
  const why = onlinePaymentProblem(c.chargeCents, currency, fees.platform);
  if (why) return compact ? null : why;
  const [total, amount, ours, stripe] = [c.chargeCents, amountCents, c.platformCents, c.processingCents - c.platformCents].map(centsLabel);
  if (compact) return `On a ${amount} fee, payers pay ${total} online and you get the whole ${amount}.`;
  return (
    `Paid online, they pay ${total}: ${amount}, plus ${ours} for Stall 10 (${platformFeeLabel(fees.platform)}) and about ${stripe} for Stripe's card fee. ` +
    `You get the whole ${amount}. Paid your own way, they pay ${amount}.`
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
}: {
  user: User | null | undefined;
  amountCents: number | null;
  currency: string;
  compact?: boolean;
}) {
  const fees = usePaymentFees(user);
  const note = fees && amountCents != null ? feeNote(fees, amountCents, currency, compact) : null;
  if (!note) return null;
  return compact ? <p className="fee-note">{note}</p> : <small className="muted fee-note">{note}</small>;
}

/** "Paid", "Paying another way", "Overdue" or "Unpaid": a fee's state on the host's lists (paymentStatusLabel in the app). */
export function paymentStatusLabel(p: PaymentDoc | undefined, overdue: boolean): string {
  if (p?.paid === true) return "Paid";
  if (p?.offlineAt) return "Paying another way";
  return overdue ? "Overdue" : "Unpaid";
}

/** Whether [p] was paid online through Stall 10 (the server's note): refunded, never ticked off by hand. */
export const isPaidOnline = (p: PaymentDoc | undefined) => p?.paid === true && p.note === paidOnlineNote;

/** "Paid online · Refund" for a fee paid through Stall 10 (the event's organizers); asks first. */
function RefundControl({ user, tournamentId, payerId, payerName, amountCents }: { user: User; tournamentId: string; payerId: string; payerName?: string; amountCents?: number }) {
  const [refunding, setRefunding] = useState(false);
  const [error, setError] = useState("");
  const refund = async () => {
    const what = amountCents ? centsLabel(amountCents) : "the fee";
    if (!window.confirm(`Refund ${what}${payerName ? ` to ${payerName}` : ""}? ${refundPolicyNote} If Stall 10 already sent you the fee, it comes back out of your payouts.`)) return;
    setRefunding(true);
    setError("");
    try {
      await callApi(user, paymentPaths.refund(encodeURIComponent(tournamentId), encodeURIComponent(payerId)), { method: "POST", body: {} });
    } catch (e) {
      setError(problem(e));
    } finally {
      setRefunding(false);
    }
  };
  return (
    <span className="host-payment">
      <span className="small">Paid online</span>
      <button type="button" className="text-btn" disabled={refunding} onClick={refund}>
        {refunding ? "Refunding…" : "Refund"}
      </button>
      {error && <small className="form-error">{error}</small>}
    </span>
  );
}

/**
 * The host's controls for one payer's fee: paid or not (shown at once,
 * undone if the save fails), the state, and a note ("Check #1042"). Saves
 * through the API, which keeps the payment history. A fee paid online
 * gets Refund instead.
 */
export function HostPaymentControls(props: {
  user: User;
  tournamentId: string;
  payerId: string;
  payment: PaymentDoc | undefined;
  overdue: boolean;
  /** For the refund's question: "Refund $400 to Haze?". */
  payerName?: string;
  amountCents?: number;
}) {
  if (isPaidOnline(props.payment)) return <RefundControl {...props} />;
  return <MarkPaymentControls {...props} />;
}

function MarkPaymentControls({ user, tournamentId, payerId, payment, overdue }: { user: User; tournamentId: string; payerId: string; payment: PaymentDoc | undefined; overdue: boolean }) {
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
