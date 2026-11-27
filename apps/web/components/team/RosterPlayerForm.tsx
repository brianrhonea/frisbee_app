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
 * Saves a roster spot in one call (`POST` or `PUT .../roster-players`): the API takes the linked member in
 * the same body (an admin's, who must be on the team; a member already on another spot is refused, and its
 * message is returned). Returns the spot's id (empty when it was not written) and an error message.
 */
export async function saveRosterPlayer(user: User, teamId: string, d: PlayerDraft): Promise<{ id: string; error: string }> {
  const body: SaveRosterPlayerRequest = {
    name: d.name.trim(),
    number: d.number === "" ? null : Number.parseInt(d.number, 10),
    position: d.position,
    userId: d.userId,
    paid: d.paid,
  };
  try {
    if (d.id) {
      await callApi(user, `${rosterBase(teamId)}/${encodeURIComponent(d.id)}`, { method: "PUT", body });
      return { id: d.id, error: "" };
    }
    const r = await callApi<{ id: string }>(user, rosterBase(teamId), { method: "POST", body });
    return { id: r.id, error: "" };
  } catch (e) {
    return { id: "", error: problem(e, "Couldn't save that. Try again.") };
  }
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
