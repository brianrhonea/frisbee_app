"use client";
import { lineSize, type StatLine, type StatSide, type StatsPlayer, sideShort } from "@stall10/shared";
import { useState } from "react";
import "./stats.css";

/** Toggle up to seven players (PlayerChooser). */
export function PlayerChooser({
  players,
  selected,
  onToggle,
}: {
  players: StatsPlayer[];
  selected: ReadonlySet<string>;
  onToggle: (id: string) => void;
}) {
  const full = selected.size >= lineSize;
  return (
    <div className="st-chooser" role="group" aria-label={`Players (${selected.size} of ${lineSize})`}>
      {players.map((p) => {
        const on = selected.has(p.id);
        return (
          <button
            key={p.id}
            type="button"
            className={`st-chip${on ? " on" : ""}`}
            aria-pressed={on}
            disabled={!on && full}
            onClick={() => onToggle(p.id)}
          >
            <b>{p.number ?? "–"}</b> {p.name}
          </button>
        );
      })}
      {players.length === 0 && <p className="muted small">No players on the roster yet.</p>}
    </div>
  );
}

export interface LineChoice {
  players: string[];
  saveAs: string | null;
  side: StatSide | null;
}

/**
 * Pick seven (showLinePicker): from a saved line or one by one, with an
 * optional name to save it as. [requireName] for building a line.
 */
export function LinePicker({
  title,
  available,
  saved = [],
  initial = [],
  requireName = false,
  canSave = false,
  defaultSide = null,
  defaultName = "",
  onDone,
}: {
  title: string;
  available: StatsPlayer[];
  saved?: StatLine[];
  initial?: string[];
  requireName?: boolean;
  canSave?: boolean;
  defaultSide?: StatSide | null;
  defaultName?: string;
  onDone: (choice: LineChoice | null) => void;
}) {
  const [picked, setPicked] = useState(() => new Set(initial));
  const [name, setName] = useState(defaultName);
  const [side, setSide] = useState<StatSide | null>(defaultSide);
  const ready = picked.size === lineSize && (!requireName || name.trim().length > 0);
  const toggle = (id: string) =>
    setPicked((s) => {
      const n = new Set(s);
      if (!n.delete(id) && n.size < lineSize) n.add(id);
      return n;
    });
  // In roster order, as the app keeps them.
  const ordered = () => available.filter((p) => picked.has(p.id)).map((p) => p.id);
  return (
    <div className="card st-subcard" role="dialog" aria-label={title}>
      <h3 className="card-title">{title}</h3>
      {saved.length > 0 && !requireName && (
        <div className="st-chips">
          {saved.map((l) => (
            <button key={l.id} type="button" className="st-chip" onClick={() => onDone({ players: l.players, saveAs: null, side: l.side })}>
              <b>{l.side ? sideShort[l.side] : "•"}</b> {l.name}
            </button>
          ))}
        </div>
      )}
      <p className="muted small">
        {requireName ? "Players" : "Custom line"} · {picked.size}/{lineSize}
      </p>
      <PlayerChooser players={available} selected={picked} onToggle={toggle} />
      {(canSave || requireName) && (
        <div className="form-row settings-form">
          <label className="field">
            <span>{requireName ? "Line name" : "Save as (optional)"}</span>
            <input value={name} maxLength={40} onChange={(e) => setName(e.target.value)} />
          </label>
          <div className="segmented" role="radiogroup" aria-label="Built for">
            {([["offense", "O"], ["defense", "D"], [null, "Either"]] as const).map(([s, label]) => (
              <button key={label} type="button" role="radio" aria-checked={side === s} className={side === s ? "on" : ""} onClick={() => setSide(s)}>
                {label}
              </button>
            ))}
          </div>
        </div>
      )}
      <div className="form-actions">
        <button type="button" className="btn btn-small" onClick={() => onDone(null)}>
          Cancel
        </button>
        <button
          type="button"
          className="btn btn-small btn-primary"
          disabled={!ready}
          onClick={() => onDone({ players: ordered(), saveAs: name.trim() || null, side })}
        >
          {picked.size < lineSize ? `Pick ${lineSize - picked.size} more` : requireName ? "Save line" : "Use line"}
        </button>
      </div>
    </div>
  );
}
