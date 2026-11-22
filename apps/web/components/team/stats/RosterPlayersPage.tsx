"use client";
import type { SaveRosterPlayerRequest, StatsPlayer } from "@stall10/shared";
import { useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useAuth } from "../../AuthProvider";
import { useTeamHub } from "../TeamContext";
import { apiUrl, statsAccess, useStatsPlayers } from "./data";
import { BackToStats, StatsGate } from "./SeasonStatsPage";
import "./stats.css";

const positions = [
  ["handler", "Handler"],
  ["cutter", "Cutter"],
  ["hybrid", "Hybrid"],
] as const;
const positionLabel = Object.fromEntries(positions) as Record<string, string>;

/**
 * Roster spots, kept for stats (the app's Roster tab): people with or
 * without an account. Admins who manage the team add, edit, mark paid,
 * link to a member and remove them; any member claims an unlinked spot as
 * theirs (their stats then show on their profile) or lets go of their own.
 */
export function RosterPlayersPage() {
  return (
    <StatsGate>
      <RosterPlayers />
    </StatsGate>
  );
}

type Draft = { id: string; name: string; number: string; position: StatsPlayer["position"]; paid: boolean; userId: string | null };
const draftOf = (p?: StatsPlayer, userId: string | null = null, name = ""): Draft => ({
  id: p?.id ?? "",
  name: p?.name ?? name,
  number: p?.number?.toString() ?? "",
  position: p?.position ?? "hybrid",
  paid: p?.paid ?? false,
  userId: p?.userId ?? userId,
});

function RosterPlayers() {
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const access = statsAccess(viewer);
  const players = useStatsPlayers(teamId, access.manageTeam);
  const [editing, setEditing] = useState<Draft | null>(null);
  const [unpaidOnly, setUnpaidOnly] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  if (viewer.state !== "member") return null;
  const team = viewer.team;
  const members = Object.keys(team.members ?? {})
    .map((uid) => ({ uid, name: team.memberNames?.[uid] || "Member" }))
    .sort((a, b) => a.name.localeCompare(b.name));
  const memberName = (uid: string | null) => (uid ? (team.memberNames?.[uid] ?? "a former member") : "");

  if (players.error) return <p className="form-error">{players.error}</p>;
  if (!players.data) return <p className="muted" aria-busy="true">Loading…</p>;
  const roster = players.data;
  const mine = roster.find((p) => p.userId === access.uid);
  const shown = unpaidOnly && access.manageTeam ? roster.filter((p) => !p.paid) : roster;
  const paidCount = roster.filter((p) => p.paid).length;

  async function run(fn: () => Promise<unknown>) {
    if (!user) return;
    setBusy(true);
    setError("");
    try {
      await fn();
      return true;
    } catch (e) {
      setError(problem(e, "Couldn't save that. Try again."));
      return false;
    } finally {
      setBusy(false);
    }
  }

  const save = async (d: Draft) => {
    const body: SaveRosterPlayerRequest = {
      name: d.name.trim(),
      number: d.number === "" ? null : Number.parseInt(d.number, 10),
      position: d.position,
      userId: d.userId,
      paid: d.paid,
    };
    const ok = await run(() =>
      callApi(user!, apiUrl(teamId, d.id ? `/roster-players/${encodeURIComponent(d.id)}` : "/roster-players"), {
        method: d.id ? "PUT" : "POST",
        body,
      }),
    );
    if (ok) setEditing(null);
  };

  const link = (p: StatsPlayer, userId: string | null) =>
    run(() => callApi(user!, apiUrl(teamId, `/roster-players/${encodeURIComponent(p.id)}/link`), { method: "PUT", body: { userId } }));

  const remove = (p: StatsPlayer) => {
    if (!window.confirm(`Remove ${p.name}?\n\nThey will be removed from the roster.`)) return;
    void run(() => callApi(user!, apiUrl(teamId, `/roster-players/${encodeURIComponent(p.id)}`), { method: "DELETE" }));
  };

  return (
    <div className="stack">
      <BackToStats teamId={teamId} />
      <h2 className="card-title">Roster players</h2>
      <p className="muted small">Everyone stats are kept for, with or without an account. A spot linked to a member counts on their profile.</p>
      {access.manageTeam && (
        <div className="home-actions">
          <button type="button" className="btn btn-primary btn-small" onClick={() => setEditing(draftOf())}>
            Add player
          </button>
          {!mine && (
            <button type="button" className="btn btn-small" onClick={() => setEditing(draftOf(undefined, access.uid, team.memberNames?.[access.uid] ?? ""))}>
              Add yourself
            </button>
          )}
        </div>
      )}
      {editing && (
        <PlayerForm
          draft={editing}
          members={members}
          linkedElsewhere={new Set(roster.filter((p) => p.id !== editing.id && p.userId).map((p) => p.userId!))}
          busy={busy}
          onCancel={() => setEditing(null)}
          onSave={save}
        />
      )}
      {error && <p className="form-error">{error}</p>}
      {access.manageTeam && roster.length > 0 && (
        <div className="toolbar">
          <span>
            {paidCount}/{roster.length} paid
          </span>
          <label className="switch-row">
            <input type="checkbox" checked={unpaidOnly} onChange={(e) => setUnpaidOnly(e.target.checked)} /> Unpaid only
          </label>
        </div>
      )}
      {roster.length === 0 ? (
        <p className="empty">No players on the roster.{access.manageTeam ? " Add players one by one." : ""}</p>
      ) : shown.length === 0 ? (
        <p className="empty">Everyone has paid.</p>
      ) : (
        <div className="card table-scroll">
          <table className="data-table roster-table">
            <thead>
              <tr>
                <th className="num">#</th>
                <th>Name</th>
                <th>Position</th>
                <th>Account</th>
                {access.manageTeam && <th>Paid</th>}
                <th>
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {shown.map((p) => (
                <tr key={p.id} className={p.userId === access.uid ? "st-you" : undefined}>
                  <td className="num st-jersey">{p.number ?? "–"}</td>
                  <td>
                    <b>{p.name}</b>
                  </td>
                  <td>{positionLabel[p.position]}</td>
                  <td className="small">
                    {p.userId === access.uid ? "You" : p.userId ? memberName(p.userId) : <span className="muted">None</span>}
                  </td>
                  {access.manageTeam && (
                    <td>
                      <button
                        type="button"
                        className={`pill st-paid${p.paid ? " on" : ""}`}
                        disabled={busy}
                        title={p.paid ? "Mark unpaid" : "Mark paid"}
                        onClick={() => save({ ...draftOf(p), paid: !p.paid })}
                      >
                        {p.paid ? "Paid" : "Unpaid"}
                      </button>
                    </td>
                  )}
                  <td className="st-actions">
                    {!p.userId && !mine && (
                      <button type="button" className="text-btn" disabled={busy} onClick={() => link(p, access.uid)}>
                        This is me
                      </button>
                    )}
                    {p.userId === access.uid && (
                      <button type="button" className="text-btn" disabled={busy} onClick={() => link(p, null)}>
                        Unlink me
                      </button>
                    )}
                    {access.manageTeam && (
                      <>
                        <button type="button" className="text-btn" onClick={() => setEditing(draftOf(p))}>
                          Edit
                        </button>
                        <button type="button" className="text-btn st-danger" disabled={busy} onClick={() => remove(p)}>
                          Remove
                        </button>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

/** Add or edit a spot (PlayerDialog). */
function PlayerForm({
  draft,
  members,
  linkedElsewhere,
  busy,
  onCancel,
  onSave,
}: {
  draft: Draft;
  members: Array<{ uid: string; name: string }>;
  linkedElsewhere: Set<string>;
  busy: boolean;
  onCancel: () => void;
  onSave: (d: Draft) => void;
}) {
  const [d, setD] = useState(draft);
  return (
    <form
      className="card settings-form"
      onSubmit={(e) => {
        e.preventDefault();
        if (d.name.trim()) onSave(d);
      }}
    >
      <h3 className="card-title">{d.id ? "Edit player" : "Add player"}</h3>
      <label className="field">
        <span>Name</span>
        <input autoFocus value={d.name} maxLength={80} onChange={(e) => setD({ ...d, name: e.target.value })} />
      </label>
      <label className="field">
        <span>Jersey number</span>
        <input inputMode="numeric" value={d.number} onChange={(e) => setD({ ...d, number: e.target.value.replace(/\D/g, "").slice(0, 3) })} />
      </label>
      <div className="segmented" role="radiogroup" aria-label="Position">
        {positions.map(([k, label]) => (
          <button key={k} type="button" role="radio" aria-checked={d.position === k} className={d.position === k ? "on" : ""} onClick={() => setD({ ...d, position: k })}>
            {label}
          </button>
        ))}
      </div>
      <label className="switch-row">
        <input type="checkbox" checked={d.paid} onChange={(e) => setD({ ...d, paid: e.target.checked })} /> Paid
        <small className="muted"> Dues or fees received</small>
      </label>
      <label className="field">
        <span>Linked account</span>
        <select value={members.some((m) => m.uid === d.userId) ? (d.userId ?? "") : ""} onChange={(e) => setD({ ...d, userId: e.target.value || null })}>
          <option value="">None</option>
          {members
            .filter((m) => !linkedElsewhere.has(m.uid))
            .map((m) => (
              <option key={m.uid} value={m.uid}>
                {m.name}
              </option>
            ))}
        </select>
        <small className="muted">Their stats show on this member&apos;s profile</small>
      </label>
      <div className="form-actions">
        <button type="button" className="btn btn-small" onClick={onCancel}>
          Cancel
        </button>
        <button type="submit" className="btn btn-small btn-primary" disabled={!d.name.trim() || busy}>
          Save
        </button>
      </div>
    </form>
  );
}
