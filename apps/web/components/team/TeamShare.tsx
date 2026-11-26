"use client";
// Splitting a team fee (TeamShareCard in the app): someone who paid for the
// whole team (a league's team fee, say) sets each member's share and how to
// pay them, and marks who has paid. No money passes through Stall 10.
// Members see their own share; nothing shows until there's one, except a
// way to start one for admins.
import {
  evenShare,
  shareTotals,
  type TeamShareView,
  teamShareLimits,
  teamShareMemberPath,
  teamSharePath,
} from "@stall10/shared";
import { type FormEvent, useCallback, useEffect, useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { Dialog } from "../Dialog";
import { useTeamHub } from "./TeamContext";
import { StatusPill } from "../ui/StatusPill";

const money = (cents: number) => `$${(cents / 100).toFixed(cents % 100 === 0 ? 0 : 2)}`;
/** Cents from what someone typed ("40", "$40.50"), or null. */
function centsOf(typed: string): number | null {
  const v = Number(typed.trim().replace(/^\$/, ""));
  if (!typed.trim() || !Number.isFinite(v) || v <= 0) return null;
  const cents = Math.round(v * 100);
  return cents > teamShareLimits.maxAmountCents ? null : cents;
}

export function TeamShare() {
  const { teamId, kind, viewer } = useTeamHub();
  const { user } = useAuth();
  const [view, setView] = useState<TeamShareView | null>(null);
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const member = viewer.state === "member";
  const people = member ? (viewer.team.memberIds?.length ?? 0) : 0;

  const load = useCallback(async () => {
    if (!user) return;
    try {
      setView(await callApi<TeamShareView>(user, teamSharePath(teamId)));
    } catch {
      // An older API, or offline: nothing to show.
      setView(null);
    }
  }, [user, teamId]);

  useEffect(() => {
    if (member && kind === "team") void load();
  }, [member, kind, load]);

  if (!member || kind !== "team" || !view || !user) return null;
  const share = view.share;

  async function run(path: string, method: string, body?: object) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      if (method === "DELETE") {
        await callApi(user, path, { method });
        setView((v) => (v ? { share: null, manages: v.manages, mine: null, members: [] } : v));
      } else {
        setView(await callApi<TeamShareView>(user, path, { method, body }));
      }
      setEditing(false);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  const dialog = editing && (
    <ShareDialog
      initial={share}
      people={people}
      busy={busy}
      error={error}
      onClose={() => {
        setEditing(false);
        setError(null);
      }}
      onSave={(amountCents, note) => void run(teamSharePath(teamId), "PUT", { amountCents, note })}
    />
  );

  if (!share) {
    if (!view.manages) return null;
    return (
      <div className="card team-share">
        <h2 className="card-title">Split a team fee</h2>
        <p className="muted small">
          Paid for the whole team, like a league&apos;s team fee? Set each person&apos;s share and how to pay you, then mark people paid as
          they do.
        </p>
        <button type="button" className="btn btn-small" onClick={() => setEditing(true)}>
          Split a fee
        </button>
        {dialog}
      </div>
    );
  }

  const t = shareTotals(share.amountCents, view.members);
  return (
    <div className="card team-share">
      <div className="card-head">
        <h2 className="card-title">Team fee</h2>
        {view.manages && (
          <span className="team-share-actions">
            <button type="button" className="text-btn small" onClick={() => setEditing(true)}>
              Change
            </button>
            <button
              type="button"
              className="text-btn small"
              disabled={busy}
              onClick={() => {
                if (window.confirm("Stop splitting the fee? Everyone's paid marks are cleared too.")) void run(teamSharePath(teamId), "DELETE");
              }}
            >
              Stop
            </button>
          </span>
        )}
      </div>
      <p className="team-share-amount">
        <b>
          {money(share.amountCents)} each, paid to {view.mine === null ? "you" : share.collectorName}
        </b>
      </p>
      {share.note && <p className="muted small team-share-note">{share.note}</p>}
      {view.mine !== null && <StatusPill tone={view.mine.paid ? "success" : "attention"} icon={view.mine.paid ? "check" : undefined}>{view.mine.paid ? "You've paid" : "Not paid yet"}</StatusPill>}
      {view.manages && (
        <>
          <p className="muted small">
            {t.paid} of {t.paid + t.owed} paid · {money(t.collectedCents)} in, {money(t.outstandingCents)} to go
          </p>
          <ul className="team-share-list">
            {view.members.map((m) => (
              <li key={m.uid}>
                <label>
                  <input
                    type="checkbox"
                    checked={m.paid}
                    disabled={busy}
                    onChange={(e) => void run(teamShareMemberPath(teamId, m.uid), "PUT", { paid: e.target.checked })}
                  />
                  <span>{m.name}</span>
                </label>
              </li>
            ))}
          </ul>
        </>
      )}
      {error && !editing && <p className="form-error">{error}</p>}
      {dialog}
    </div>
  );
}

function ShareDialog({
  initial,
  people,
  busy,
  error,
  onClose,
  onSave,
}: {
  initial: TeamShareView["share"];
  people: number;
  busy: boolean;
  error: string | null;
  onClose: () => void;
  onSave: (amountCents: number, note: string) => void;
}) {
  const [total, setTotal] = useState("");
  const [amount, setAmount] = useState(initial ? (initial.amountCents / 100).toFixed(initial.amountCents % 100 === 0 ? 0 : 2) : "");
  const [note, setNote] = useState(initial?.note ?? "");
  const [problem, setProblem] = useState<string | null>(null);

  function split(typed: string) {
    setTotal(typed);
    const cents = centsOf(typed);
    if (cents != null) setAmount((evenShare(cents, people) / 100).toFixed(2));
  }

  function save(e: FormEvent) {
    e.preventDefault();
    const cents = centsOf(amount);
    if (cents == null) {
      setProblem("Enter each person's share, e.g. 40.");
      return;
    }
    setProblem(null);
    onSave(cents, note.trim());
  }

  return (
    <Dialog label={initial ? "Team fee" : "Split a team fee"} onClose={onClose} className="card" dismissOnBackdrop>
      <form className="settings-form" onSubmit={save}>
        <h2 className="card-title">{initial ? "Team fee" : "Split a team fee"}</h2>
        <label>
          Total fee <small className="muted">(optional)</small>
          <input inputMode="decimal" value={total} placeholder="$" onChange={(e) => split(e.target.value)} />
          <small className="muted">Split evenly among the {people} people on the team, you included.</small>
        </label>
        <label>
          Each person&apos;s share
          <input inputMode="decimal" value={amount} required placeholder="$" onChange={(e) => setAmount(e.target.value)} />
        </label>
        <label>
          How to pay you
          <textarea
            value={note}
            rows={2}
            maxLength={teamShareLimits.note}
            placeholder="e.g. Venmo @alex, or cash at practice"
            onChange={(e) => setNote(e.target.value)}
          />
        </label>
        {(problem ?? error) && <p className="form-error">{problem ?? error}</p>}
        <div className="form-actions">
          <button type="button" className="btn" onClick={onClose}>
            Cancel
          </button>
          <button type="submit" className="btn btn-primary" disabled={busy}>
            {busy ? "Saving…" : "Save"}
          </button>
        </div>
      </form>
    </Dialog>
  );
}
