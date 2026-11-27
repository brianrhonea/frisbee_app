"use client";
// Stall 10 staff's view of every payment through Stall 10 (Stall 10
// collects fees and pays hosts out): problems the daily check against
// Stripe found, the latest payments, and the two staff actions: send what's
// due to hosts now, and check everything against Stripe now. Ids and
// amounts only; card and bank details stay with Stripe. A staff tool, on
// the website only (as the report queue).
import {
  centsLabel,
  type PaymentIssueKind,
  paymentIssueLabels,
  paymentPaths,
  payoutReviewLabels,
  type ReconcileResult,
  type ReleaseResult,
  type StaffChargeView,
  type StaffPaymentsView,
} from "@stall10/shared";
import { useCallback, useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { ErrorNote } from "@/components/StatusViews";

const statusLabels: Record<string, string> = {
  open: "Not paid yet",
  processing: "Bank payment clearing",
  paid: "Paid",
  failed: "Failed",
  expired: "Expired",
  refunding: "Refunding",
  refunded: "Refunded",
  disputed: "Disputed",
  duplicate: "Duplicate, refunded",
};

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" }) : "—");

/** Where the host's share stands. */
function payoutLabel(c: StaffChargeView): string {
  if (c.kept) return "Stall 10 event";
  if (c.reversed) return c.owedCents > 0 ? `Owed ${centsLabel(c.owedCents)}` : "Taken back";
  if (c.released) return `Sent ${centsLabel(c.transferCents)}`;
  if (c.review) return `Held: ${payoutReviewLabels[c.review]}`;
  return c.status === "paid" ? "Held" : "—";
}

export function StaffPayments() {
  const { user } = useAuth();
  const [view, setView] = useState<StaffPaymentsView | null>(null);
  const [tournament, setTournament] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState("");
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    if (!user) return;
    try {
      const q = tournament.trim() ? `?tournament=${encodeURIComponent(tournament.trim())}` : "";
      setView(await callApi<StaffPaymentsView>(user, `${paymentPaths.staff}${q}`));
      setError("");
    } catch (e) {
      setError(problem(e, "Couldn't load the payments."));
    }
  }, [user, tournament]);
  useEffect(() => {
    void load();
  }, [load]);

  /** Staff approve a host's first (or a large) payout; it goes out if it's due. */
  async function approve(c: StaffChargeView) {
    if (!user) return;
    const ask = `Send ${centsLabel(c.baseCents)} for "${c.label || c.payerId}" to the host? Check the host and the event look genuine first.`;
    if (!window.confirm(ask)) return;
    setBusy(c.id);
    setError("");
    try {
      const r = await callApi<{ status: "sent" | "held" }>(user, paymentPaths.approve(c.id), { method: "POST", body: {} });
      setNote(r.status === "sent" ? "Approved and sent." : "Approved. It goes out once it's due.");
      await load();
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(null);
    }
  }

  async function run(what: "release" | "check") {
    if (!user) return;
    setBusy(what);
    setError("");
    setNote("");
    try {
      if (what === "release") {
        const r = await callApi<ReleaseResult>(user, paymentPaths.release, { method: "POST", body: {} });
        setNote(`Checked ${r.checked} held ${r.checked === 1 ? "fee" : "fees"}; sent ${r.sent}.`);
      } else {
        const r = await callApi<ReconcileResult>(user, paymentPaths.reconcile, { method: "POST", body: {} });
        setNote(`Checked ${r.checked} with Stripe: ${r.issues} with a problem, ${r.resolved} fixed since last time.`);
      }
      await load();
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(null);
    }
  }

  if (!view) return error ? <ErrorNote>{error}</ErrorNote> : <p className="muted" aria-busy="true">Loading payments…</p>;
  if (!view.available) return <p className="empty">Online payments aren&apos;t set up on this server.</p>;
  return (
    <div className="stack staff-payments">
      <div className="home-actions">
        <button type="button" className="btn btn-small" disabled={busy !== null} onClick={() => run("release")}>
          {busy === "release" ? "Sending…" : "Send what's due to hosts"}
        </button>
        <button type="button" className="btn btn-small" disabled={busy !== null} onClick={() => run("check")}>
          {busy === "check" ? "Checking…" : "Check against Stripe"}
        </button>
        <span className="muted small">Last checked: {view.checkedAt ? new Date(view.checkedAt).toLocaleString() : "never"}</span>
      </div>
      {note && <p className="muted small">{note}</p>}
      {error && <ErrorNote>{error}</ErrorNote>}

      {view.charges.some((c) => c.review) && (
        <section className="card">
          <h2 className="card-title">Waiting for approval</h2>
          <p className="muted small">A host&apos;s first payout and large ones wait for staff. Check the host team and event are real (and the payers aren&apos;t all new cards) before approving.</p>
          <ul className="stack">
            {view.charges
              .filter((c) => c.review)
              .map((c) => (
                <li key={c.id} className="staff-payment-issue">
                  <strong>{c.label || c.payerId}</strong> · {centsLabel(c.baseCents)} · {payoutReviewLabels[c.review!]} ·{" "}
                  <a className="text-btn" href={`/tournaments/${encodeURIComponent(c.tournamentId)}`}>
                    event
                  </a>{" "}
                  <button type="button" className="btn btn-small" disabled={busy !== null} onClick={() => void approve(c)}>
                    {busy === c.id ? "Approving…" : "Approve"}
                  </button>
                  <br />
                  <small className="muted">
                    Host <code>{c.hostId}</code> · <code>{c.id}</code>
                  </small>
                </li>
              ))}
          </ul>
        </section>
      )}

      <section className="card">
        <h2 className="card-title">Problems ({view.issues.length})</h2>
        {view.issues.length === 0 ? (
          <p className="muted">Nothing to look at: every payment matches Stripe.</p>
        ) : (
          <ul className="stack">
            {view.issues.map((i) => (
              <li key={i.id} className="staff-payment-issue">
                <strong>{i.label || "Payment"}</strong>{" "}
                <a className="text-btn" href={`/tournaments/${encodeURIComponent(i.tournamentId)}`}>
                  event
                </a>
                <ul>
                  {i.kinds.map((k: PaymentIssueKind) => (
                    <li key={k}>{paymentIssueLabels[k] ?? k}</li>
                  ))}
                </ul>
                <small className="muted">
                  {i.detail} · since {day(i.firstSeenAt)} · <code>{i.id}</code>
                </small>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="card">
        <div className="card-head">
          <h2 className="card-title">Latest payments</h2>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void load();
            }}
          >
            <input id="staff-payments-tournament" aria-label="Event id" placeholder="Event id (optional)" value={tournament} onChange={(e) => setTournament(e.target.value)} />
          </form>
        </div>
        {view.charges.length === 0 ? (
          <p className="muted">No payments yet.</p>
        ) : (
          <div className="table-scroll">
            <table className="staff-payments-table">
              <thead>
                <tr>
                  <th>Paid</th>
                  <th>For</th>
                  <th>Status</th>
                  <th>Charged</th>
                  <th>Fee</th>
                  <th>Host</th>
                  <th>Stripe id</th>
                </tr>
              </thead>
              <tbody>
                {view.charges.map((c) => (
                  <tr key={c.id}>
                    <td>{day(c.paidAt ?? c.createdAt)}</td>
                    <td>
                      <a href={`/tournaments/${encodeURIComponent(c.tournamentId)}`}>{c.label || c.payerId}</a>
                    </td>
                    <td>{statusLabels[c.status] ?? c.status}</td>
                    <td className="num">{centsLabel(c.amountCents)}</td>
                    <td className="num">{c.refundCents > 0 ? `${centsLabel(c.baseCents)} (refunded ${centsLabel(c.refundCents)})` : centsLabel(c.baseCents)}</td>
                    <td>{payoutLabel(c)}</td>
                    <td>
                      <code>{c.id}</code>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
