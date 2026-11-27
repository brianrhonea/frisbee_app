"use client";
import type { SaveRosterPlayerRequest, StatsPlayer } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useState } from "react";
import { callApi, problem } from "@/lib/client";
import { ErrorNote } from "../StatusViews";
import "./roster_actions.css";

/** One roster spot as the form edits it (the app's PlayerDialog). */
export type PlayerDraft = {
  id: string;
  name: string;
  number: string;
  position: StatsPlayer["position"];
  paid: boolean;
  /** The member the spot is linked to, or none. */
  userId: string | null;
};

export const positions = [
  ["handler", "Handler"],
  ["cutter", "Cutter"],
  ["hybrid", "Hybrid"],
] as const;

export const draftOf = (p?: StatsPlayer, userId: string | null = null, name = ""): PlayerDraft => ({
  id: p?.id ?? "",
  name: p?.name ?? name,
  number: p?.number?.toString() ?? "",
  position: p?.position ?? "hybrid",
  paid: p?.paid ?? false,
  userId: p?.userId ?? userId,
});

const rosterBase = (teamId: string) => `/v1/teams/${encodeURIComponent(teamId)}/roster-players`;

/**
 * Saves a roster spot the way the API owns it: the spot first (`POST` or `PUT .../roster-players`, always
 * unlinked or as it was), then the link to a member through the admin link call (`PUT .../:id/link`).
 * Wave 1 of the owner's "easy linking": a later API change may let the create take the member directly.
 * `was` is the link the spot already had. Returns the spot's id (empty when it was not written) and an error message (empty when both calls went
 * through), so a failed link can be retried as an edit rather than adding the spot twice.
 */
export async function saveRosterPlayer(
  user: User,
  teamId: string,
  d: PlayerDraft,
  was: string | null,
): Promise<{ id: string; error: string }> {
  const body: SaveRosterPlayerRequest = {
    name: d.name.trim(),
    number: d.number === "" ? null : Number.parseInt(d.number, 10),
    position: d.position,
    userId: d.id ? was : null,
    paid: d.paid,
  };
  let id = d.id;
  try {
    if (id) await callApi(user, `${rosterBase(teamId)}/${encodeURIComponent(id)}`, { method: "PUT", body });
    else id = (await callApi<{ id: string }>(user, rosterBase(teamId), { method: "POST", body })).id;
  } catch (e) {
    return { id: d.id, error: problem(e, "Couldn't save that. Try again.") };
  }
  if (d.userId !== was) {
    try {
      await callApi(user, `${rosterBase(teamId)}/${encodeURIComponent(id)}/link`, { method: "PUT", body: { userId: d.userId } });
    } catch (e) {
      return { id, error: `Saved, but couldn't link the member: ${problem(e, "Try again.")}` };
    }
  }
  return { id, error: "" };
}

/**
 * Add or edit a roster spot. "Link to a member" lists the team's members who are not yet linked to a spot
 * (and the spot's own member when editing); picking one fills the name from their profile name.
 */
export function RosterPlayerForm({
  draft,
  members,
  linkedElsewhere,
  busy,
  error,
  onCancel,
  onSave,
}: {
  draft: PlayerDraft;
  members: Array<{ uid: string; name: string }>;
  /** Members already linked to another spot. */
  linkedElsewhere: Set<string>;
  busy: boolean;
  error?: string;
  onCancel: () => void;
  onSave: (d: PlayerDraft) => void;
}) {
  const [d, setD] = useState(draft);
  // The name a pick filled in, so a later pick replaces it but never a name someone typed.
  const [filled, setFilled] = useState("");
  const choices = members.filter((m) => !linkedElsewhere.has(m.uid));
  function pick(uid: string) {
    const m = members.find((x) => x.uid === uid);
    if (!m) return setD({ ...d, userId: null });
    const keep = d.name.trim() !== "" && d.name !== filled;
    setD({ ...d, userId: uid, name: keep ? d.name : m.name });
    setFilled(m.name);
  }
  return (
    <form
      className="settings-form roster-player-form"
      onSubmit={(e) => {
        e.preventDefault();
        if (d.name.trim()) onSave(d);
      }}
    >
      <h3 className="card-title">{d.id ? "Edit player" : "Add player to roster"}</h3>
      <label className="field">
        <span>Link to a member</span>
        <select value={members.some((m) => m.uid === d.userId) ? (d.userId ?? "") : ""} onChange={(e) => pick(e.target.value)}>
          <option value="">Not linked (no account)</option>
          {choices.map((m) => (
            <option key={m.uid} value={m.uid}>
              {m.name}
            </option>
          ))}
        </select>
        <small className="muted">Their stats show on this member&apos;s profile. Picking one fills the name.</small>
      </label>
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
      {error && <ErrorNote>{error}</ErrorNote>}
      <div className="form-actions">
        <button type="button" className="btn btn-small" onClick={onCancel}>
          Cancel
        </button>
        <button type="submit" className="btn btn-small btn-primary" disabled={!d.name.trim() || busy}>
          {busy ? "Saving…" : "Save"}
        </button>
      </div>
    </form>
  );
}
