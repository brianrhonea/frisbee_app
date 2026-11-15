"use client";
import { formatStat, type StatSheet, statColumns } from "@stall10/shared";
import { useState } from "react";
import "./stats.css";

const pct = (v: number | null) => (v === null ? "–" : `${Math.round(v * 100)}%`);

/**
 * Sortable per-player stats (StatSheetTable in the app): team O efficiency
 * and break rate on top, the player column pinned while the numbers scroll.
 */
export function StatSheetTable({ sheet, nameOf }: { sheet: StatSheet; nameOf: (id: string) => string }) {
  const [sort, setSort] = useState(0);
  const [ascending, setAscending] = useState(false);
  const [glossary, setGlossary] = useState(false);
  if (sheet.players.size === 0) return <p className="empty">No stats yet. Stats appear once points are tracked.</p>;
  const col = statColumns[sort];
  const rows = [...sheet.players.values()].sort((a, b) => {
    const va = col.value(a) ?? -1;
    const vb = col.value(b) ?? -1;
    return ascending ? va - vb : vb - va;
  });
  const t = sheet.team;
  return (
    <div className="stack">
      <div className="tiles st-eff">
        <div className="tile">
          <b>{pct(t.oEfficiency)}</b>
          <small>
            O efficiency · {t.holds} of {t.oPoints} O points scored
          </small>
        </div>
        <div className="tile">
          <b>{pct(t.breakRate)}</b>
          <small>
            Break rate · {t.breaks} of {t.dPoints} D points broken
          </small>
        </div>
      </div>
      <div className="card table-scroll st-sheet">
        <table className="data-table stats-table">
          <thead>
            <tr>
              <th className="st-pin">Player</th>
              {statColumns.map((c, i) => (
                <th key={c.label} className="num" title={c.tooltip} aria-sort={i === sort ? (ascending ? "ascending" : "descending") : "none"}>
                  <button
                    type="button"
                    className="st-sort"
                    onClick={() => {
                      if (i === sort) setAscending(!ascending);
                      else {
                        setSort(i);
                        setAscending(false);
                      }
                    }}
                  >
                    {c.label}
                    {i === sort ? (ascending ? " ▲" : " ▼") : ""}
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((p) => (
              <tr key={p.playerId}>
                <td className="st-pin">{nameOf(p.playerId)}</td>
                {statColumns.map((c, i) => (
                  <td key={c.label} className={`num${i === 0 ? (p.plusMinus < 0 ? " st-neg" : " st-pos") : ""}`}>
                    {formatStat(c, p)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <button type="button" className="text-btn" onClick={() => setGlossary(!glossary)} aria-expanded={glossary}>
        Stat key: what each column means
      </button>
      {glossary && <StatsGlossary />}
    </div>
  );
}

/** What each column means and how the score and ratings are worked out (stats_glossary.dart, in short). */
function StatsGlossary() {
  return (
    <div className="card">
      <dl className="glossary">
        {statColumns.map((c) => (
          <div key={c.label}>
            <dt>{c.label}</dt>
            <dd>{c.tooltip}</dd>
          </div>
        ))}
        <div>
          <dt>Score (+/-)</dt>
          <dd>Goal and assist +1, hand block +2, D (breakup) +1; a throwaway, drop or getting beat −1. Pulls don&apos;t count.</dd>
        </div>
        <div>
          <dt>Ratings</dt>
          <dd>
            Per finished point: 1 if we scored, plus 0.5 per goal or assist, 0.1 per touch, 1 per hand block and 0.5 per breakup; each
            throwaway or drop costs 0.75 either way. Averaged and shown ×100.
          </dd>
        </div>
      </dl>
    </div>
  );
}
