"use client";
import {
  type GameTracker,
  gameWon,
  halfAt,
  halftimePoint,
  lineSize,
  ourScore,
  played,
  reachedGamePoint,
  type StatAction,
  type StatKind,
  type StatLine,
  type StatSide,
  sideShort,
  theirScore,
  turnsOver,
} from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { useAuth } from "../../AuthProvider";
import { useTeamHub } from "../TeamContext";
import { apiUrl, dateTime, tournamentUrl } from "./data";
import { LinePicker, PlayerChooser } from "./LinePicker";
import { GameSettings } from "./NewStatsForm";
import { PullTimer } from "./PullTimer";
import { BackToStats, StatsGate } from "./SeasonStatsPage";
import { StatSheetTable } from "./StatSheetTable";
import { confirmAndDelete, deleteGameMessage } from "./StatsHome";
import { useGameTracker } from "./useTracker";
import "./stats.css";
import { isTyping } from "@/lib/text";
import { Dialog } from "../../Dialog";

type Tab = "track" | "lines" | "points" | "stats";
type Act = (fn: (t: GameTracker) => void) => void;
const halfName = (h: number) => (h === 1 ? "1st half" : "2nd half");

/** One game (GameScreen): track it live, its lines, the point log and the box score. */
export function GamePage({ gameId }: { gameId: string }) {
  return (
    <StatsGate>
      <Game gameId={gameId} />
    </StatsGate>
  );
}

function Game({ gameId }: { gameId: string }) {
  const { teamId } = useTeamHub();
  const { user } = useAuth();
  const router = useRouter();
  const { tracker: t, act, loaded, error, saveError, canDelete } = useGameTracker(gameId);
  const [tab, setTab] = useState<Tab>("track");
  const [panel, setPanel] = useState<"gameTo" | "timeouts" | null>(null);
  const [deleteError, setDeleteError] = useState("");

  if (!loaded && !error) return <p className="muted" aria-busy="true">Loading…</p>;
  if (!t) {
    return (
      <div className="stack">
        <BackToStats teamId={teamId} />
        {error ? <p className="form-error">{error}</p> : <p className="empty">Game not found.</p>}
      </div>
    );
  }
  const g = t.game;
  const back = t.tournament ? (
    <Link href={tournamentUrl(teamId, t.tournament.id)} className="text-btn">
      ← {t.tournament.name}
    </Link>
  ) : (
    <BackToStats teamId={teamId} />
  );

  return (
    <div className="stack st-game">
      {back}
      <div className="st-game-head">
        <div>
          <h2 className="card-title">vs {g.opponent}</h2>
          <p className="muted small">{t.tournament?.name ?? dateTime(g.date)}</p>
        </div>
        {t.canEdit && (
          <div className="home-actions">
            <button type="button" className="btn btn-small" onClick={() => setPanel(panel === "gameTo" ? null : "gameTo")}>
              Change game point
            </button>
            <button type="button" className="btn btn-small" onClick={() => setPanel(panel === "timeouts" ? null : "timeouts")}>
              Timeouts
            </button>
            <button
              type="button"
              className="btn btn-small"
              onClick={() => {
                if (g.finished) act((x) => x.setFinished(false));
                else if (window.confirm(`End game early?\n\nFor a time cap or forfeit. Final score ${ourScore(g)}–${theirScore(g)}.`)) {
                  act((x) => x.setFinished(true));
                }
              }}
            >
              {g.finished ? "Resume tracking" : "End game early"}
            </button>
            {canDelete && user && (
              <button
                type="button"
                className="btn btn-small btn-danger"
                onClick={async () => {
                  if (await confirmAndDelete(user, apiUrl(teamId, `/stats-games/${encodeURIComponent(g.id)}`), deleteGameMessage(g), setDeleteError)) {
                    router.push(t.tournament ? tournamentUrl(teamId, t.tournament.id) : `/teams/${encodeURIComponent(teamId)}/stats`);
                  }
                }}
              >
                Delete game
              </button>
            )}
          </div>
        )}
      </div>
      {deleteError && <p className="form-error">{deleteError}</p>}
      {panel === "gameTo" && <GameToPanel t={t} act={act} onClose={() => setPanel(null)} />}
      {panel === "timeouts" && <TimeoutsPanel t={t} act={act} onClose={() => setPanel(null)} />}

      <div className="segmented" role="tablist" aria-label="Game">
        {(
          [
            ["track", "Track"],
            ["lines", "Lines"],
            ["points", "Points"],
            ["stats", "Stats"],
          ] as const
        ).map(([k, label]) => (
          <button key={k} type="button" role="tab" aria-selected={tab === k} className={tab === k ? "on" : ""} onClick={() => setTab(k)}>
            {label}
          </button>
        ))}
      </div>
      {tab === "track" && (
        <TrackTab t={t} act={act} saveError={saveError} onLines={() => setTab("lines")} onStats={() => setTab("stats")} onGameTo={() => setPanel("gameTo")} onTimeouts={() => setPanel("timeouts")} />
      )}
      {tab === "lines" && <LinesTab t={t} act={act} />}
      {tab === "points" && <PointLog t={t} />}
      {tab === "stats" && <StatSheetTable sheet={t.sheet} nameOf={(id) => t.nameOf(id)} />}
    </div>
  );
}

// ---- Game point and timeouts -------------------------------------------------------

function GameToPanel({ t, act, onClose }: { t: GameTracker; act: Act; onClose: () => void }) {
  const g = t.game;
  const minimum = Math.max(ourScore(g), theirScore(g));
  return (
    <div className="card st-subcard settings-form">
      <h3 className="card-title">Game to</h3>
      <GameSettings
        gameTo={g.gameTo}
        timeouts={g.timeoutsPerHalf}
        minimum={minimum}
        onGameTo={(n) => {
          act((x) => x.setGameTo(n));
          onClose();
        }}
        onTimeouts={(n) => act((x) => x.setTimeoutsPerHalf(n))}
      />
      {reachedGamePoint(g) && <p className="muted small">At {minimum} the current score is game over; pick higher to keep tracking.</p>}
      <button type="button" className="text-btn" onClick={onClose}>
        Close
      </button>
    </div>
  );
}

function TimeoutsPanel({ t, act, onClose }: { t: GameTracker; act: Act; onClose: () => void }) {
  const g = t.game;
  const half = t.half;
  const thisHalf = g.timeouts.map((x, i) => ({ x, i })).filter(({ x }) => x.half === half);
  const team = (ours: boolean) => {
    const left = t.timeoutsLeft(ours);
    return (
      <div className="st-timeout-team">
        <b>{ours ? "Us" : g.opponent}</b>
        <span className="st-dots" aria-label={`${left} left`}>
          {Array.from({ length: g.timeoutsPerHalf }, (_, n) => (
            <i key={n} className={n < left ? "on" : ""} />
          ))}
        </span>
        <small className="muted">{left} left</small>
        <button type="button" className="btn btn-small" disabled={!t.canCallTimeout(ours)} onClick={() => act((x) => x.callTimeout(ours))}>
          Call timeout
        </button>
      </div>
    );
  };
  return (
    <div className="card st-subcard">
      <h3 className="card-title">Timeouts · {halfName(half)}</h3>
      <p className="muted small">{half === 1 ? `Halftime at ${halfAt(g)}. Timeouts reset for the 2nd half.` : "Second half."}</p>
      <div className="st-row">
        {team(true)}
        {team(false)}
      </div>
      {thisHalf.length > 0 && (
        <>
          <h4 className="card-title">Called this half</h4>
          <ul className="st-plain">
            {thisHalf.reverse().map(({ x, i }) => (
              <li key={i}>
                {x.ours ? "Us" : g.opponent} · Point {x.point + 1}
                {t.canEdit && (
                  <button type="button" className="text-btn" onClick={() => act((y) => y.removeTimeout(i))} aria-label="Remove timeout">
                    Remove
                  </button>
                )}
              </li>
            ))}
          </ul>
        </>
      )}
      {t.canEdit && (
        <div className="settings-form">
          <GameSettings gameTo={g.gameTo} timeouts={g.timeoutsPerHalf} onGameTo={(n) => act((x) => x.setGameTo(n))} onTimeouts={(n) => act((x) => x.setTimeoutsPerHalf(n))} minimum={Math.max(ourScore(g), theirScore(g))} />
        </div>
      )}
      <button type="button" className="text-btn" onClick={onClose}>
        Close
      </button>
    </div>
  );
}

// ---- Track ----------------------------------------------------------------------------------

const keyHelp: Array<[string, string]> = [
  ["1–7", "tap a player on the field"],
  ["G", "score"],
  ["T", "throwaway"],
  ["X", "drop"],
  ["B", "D (+1)"],
  ["H", "hand block (+2)"],
  ["N", "got beat (−1)"],
  ["W", "their turnover"],
  ["O", "they scored"],
  ["P", "pull"],
  ["U / Ctrl+Z", "undo"],
  ["Esc", "cancel"],
  ["Enter", "start point"],
];

function TrackTab({
  t,
  act,
  saveError,
  onLines,
  onStats,
  onGameTo,
  onTimeouts,
}: {
  t: GameTracker;
  act: Act;
  saveError: string | null;
  onLines: () => void;
  onStats: () => void;
  onGameTo: () => void;
  onTimeouts: () => void;
}) {
  const [overlay, setOverlay] = useState<"pull" | "line" | "sub" | "save" | null>(null);
  const [subOut, setSubOut] = useState<string | null>(null);
  const [help, setHelp] = useState(false);
  const point = t.currentPoint;
  const tracking = t.canEdit && point !== null && !t.over;
  const pickingLine = t.canEdit && point === null && !t.over;

  const startDraft = () => {
    act((x) => x.startDraft());
    if (t.canPull) setOverlay("pull");
  };

  // Keyboard shortcuts while tracking (not while typing or in a dialog).
  useEffect(() => {
    if (!t.canEdit) return;
    const onKey = (e: KeyboardEvent) => {
      if (isTyping(e.target)) return;
      if (overlay) {
        if (e.key === "Escape" && overlay !== "pull") setOverlay(null);
        return;
      }
      if (e.altKey || e.metaKey) return;
      const k = e.key.toLowerCase();
      if ((e.ctrlKey && k === "z") || (!e.ctrlKey && k === "u")) {
        e.preventDefault();
        act((x) => x.undo());
        return;
      }
      if (e.ctrlKey) return;
      if (k === "escape") return act((x) => x.armed && x.undo());
      if (k === "enter" && pickingLine && t.draftReady) return startDraft();
      if (/^[1-9]$/.test(k)) {
        const id = t.onField[Number(k) - 1];
        if (id) act((x) => x.tapPlayer(id));
        return;
      }
      const arm = ({ g: "goal", x: "drop", b: "breakup", h: "handBlock", n: "beat" } as Record<string, StatKind>)[k];
      if (arm) return act((x) => x.arm(arm));
      if (k === "t") return act((x) => x.throwaway());
      if (k === "w") return act((x) => x.weGotIt());
      if (k === "o") return act((x) => x.theyScored());
      if (k === "p" && t.canPull) setOverlay("pull");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  return (
    <div className="stack">
      {saveError && <p className="form-error st-banner">{saveError}</p>}
      <Scoreboard t={t} act={act} onGameTo={onGameTo} onTimeouts={onTimeouts} />
      {t.over ? (
        <GameOver t={t} onStats={onStats} onGameTo={onGameTo} />
      ) : !t.canEdit ? (
        <p className="st-banner">View only. Coaches and owners keep stats; follow along in Points and Stats.</p>
      ) : point === null ? (
        <LineupCard t={t} act={act} onLines={onLines} onSave={() => setOverlay("save")} />
      ) : (
        <>
          <LineBar t={t} onChange={() => setOverlay("line")} onSub={() => setOverlay("sub")} />
          <StatusBanner t={t} />
          <PlayerGrid t={t} act={act} />
        </>
      )}

      {overlay === "pull" && (
        <PullTimer
          pullers={t.onField.map((id) => ({ id, name: t.nameOf(id) }))}
          initial={t.lastPuller}
          onDone={(p) => {
            setOverlay(null);
            if (p) act((x) => x.recordPull(p.playerId, p.hangTimeMs, p.outOfBounds));
          }}
        />
      )}
      {overlay === "line" && (
        <LinePicker
          title={`Line for point ${t.pointNumber} (${sideShort[t.side]})`}
          available={t.available}
          saved={t.linesFor(t.side)}
          initial={point?.line ?? []}
          canSave
          defaultSide={t.side}
          onDone={(c) => {
            setOverlay(null);
            if (c) act((x) => x.useLine(c.players, c.saveAs ? { name: c.saveAs, side: c.side } : undefined));
          }}
        />
      )}
      {overlay === "save" && (
        <LinePicker
          title="New line"
          available={t.available}
          initial={[...t.draft]}
          requireName
          defaultSide={t.nextSide}
          onDone={(c) => {
            setOverlay(null);
            if (c) act((x) => x.saveLine(c.saveAs ?? "Line", c.players, { side: c.side }));
          }}
        />
      )}
      {overlay === "sub" && (
        <Dialog
          label="Substitution"
          onClose={() => {
            setSubOut(null);
            setOverlay(null);
          }}
          className="card st-subcard"
        >
          <h3 className="card-title">{subOut ? `Who's going in for ${t.nameOf(subOut)}?` : "Who's coming off?"}</h3>
          <div className="st-chips">
            {(subOut ? t.bench.map((p) => p.id) : t.onField).map((id) => (
              <button
                key={id}
                type="button"
                className="st-chip"
                disabled={!subOut && !t.canSubOut(id)}
                onClick={() => {
                  if (!subOut) setSubOut(id);
                  else {
                    act((x) => x.substitute(subOut, id));
                    setSubOut(null);
                    setOverlay(null);
                  }
                }}
              >
                <b>{t.player(id)?.number ?? "–"}</b> {t.nameOf(id)}
                {!subOut && id === t.holder && <small> · has the disc; the sub takes it and throws next</small>}
              </button>
            ))}
          </div>
          <button
            type="button"
            className="text-btn"
            onClick={() => {
              if (subOut) setSubOut(null);
              else setOverlay(null);
            }}
          >
            {subOut ? "Back" : "Cancel"}
          </button>
        </Dialog>
      )}

      {(tracking || pickingLine || (t.over && t.canUndo)) && (
        <div className="card st-dock">
          <UndoBar t={t} act={act} />
          {!t.over &&
            (pickingLine ? (
              <StartBar t={t} onStart={startDraft} />
            ) : t.side === "offense" ? (
              <OffenseActions t={t} act={act} />
            ) : (
              <DefenseActions t={t} act={act} onPull={() => setOverlay("pull")} />
            ))}
        </div>
      )}
      {t.canEdit && (
        <>
          <button type="button" className="text-btn" onClick={() => setHelp(!help)} aria-expanded={help}>
            Keyboard shortcuts
          </button>
          {help && (
            <dl className="st-keys">
              {keyHelp.map(([k, v]) => (
                <div key={k}>
                  <dt>
                    <kbd>{k}</kbd>
                  </dt>
                  <dd>{v}</dd>
                </div>
              ))}
            </dl>
          )}
        </>
      )}
    </div>
  );
}

function Scoreboard({ t, act, onGameTo, onTimeouts }: { t: GameTracker; act: Act; onGameTo: () => void; onTimeouts: () => void }) {
  const g = t.game;
  return (
    <div className="card st-scoreboard">
      <div className="st-score-row">
        <div className="st-team">
          <small>Us</small>
          <b>{ourScore(g)}</b>
        </div>
        <div className="st-mid">
          <small>{t.over ? "FINAL" : `Point ${t.pointNumber}`}</small>
          <button type="button" className="pill" disabled={!t.canEdit} onClick={onGameTo}>
            Game to {g.gameTo}
          </button>
        </div>
        <div className="st-team">
          <small className="st-ellipsis">{g.opponent}</small>
          <b>{theirScore(g)}</b>
          {t.canEdit && (
            <button type="button" className="text-btn" disabled={!t.canOpponentScore} onClick={() => act((x) => x.theyScored())}>
              + Opp score
            </button>
          )}
        </div>
      </div>
      <div className="segmented st-sides" role="radiogroup" aria-label="Side">
        {(["offense", "defense"] as const).map((s) => (
          <button key={s} type="button" role="radio" aria-checked={t.side === s} className={t.side === s ? "on" : ""} disabled={!t.canSetSide} onClick={() => act((x) => x.setSide(s))}>
            On {sideShort[s]}
          </button>
        ))}
      </div>
      {g.timeoutsPerHalf > 0 && (
        <button type="button" className="btn btn-small st-wide" onClick={onTimeouts}>
          Timeouts · Us {t.timeoutsLeft(true)} · Them {t.timeoutsLeft(false)} · {halfName(t.half)}
        </button>
      )}
    </div>
  );
}

function GameOver({ t, onStats, onGameTo }: { t: GameTracker; onStats: () => void; onGameTo: () => void }) {
  const g = t.game;
  const won = gameWon(g);
  const result = won === true ? "We won" : won === false ? "We lost" : "Tied";
  return (
    <div className="card">
      <h3 className="card-title">
        Game over · {result} {ourScore(g)}–{theirScore(g)}
      </h3>
      <p className="muted small">
        {g.finished
          ? "Ended early. Resume tracking above to continue."
          : `Someone reached ${g.gameTo}. If the game is to a higher score, change game point to keep tracking.`}
      </p>
      <div className="home-actions">
        {!g.finished && t.canEdit && (
          <button type="button" className="btn btn-small btn-primary" onClick={onGameTo}>
            Change game point
          </button>
        )}
        <button type="button" className="btn btn-small" onClick={onStats}>
          View stats
        </button>
      </div>
    </div>
  );
}

/** Between points: pick the next seven (_LineupCard). */
function LineupCard({ t, act, onLines, onSave }: { t: GameTracker; act: Act; onLines: () => void; onSave: () => void }) {
  const side = t.nextSide;
  const last = t.lastLineFor(side);
  const lines = t.linesFor(side);
  const picked = t.draft;
  const showing = (ids: string[]) => ids.length === picked.size && ids.every((id) => picked.has(id));
  const previous = t.points[t.points.length - 1];
  return (
    <div className="card">
      {previous?.result && (
        <p className={previous.result === "weScored" ? "st-pos" : "st-neg"}>
          <b>
            {previous.result === "weScored"
              ? previous.startedOn === "defense"
                ? "Break! Now we pull."
                : "We scored! Now we pull."
              : `${t.game.opponent} scored. We receive.`}
          </b>
        </p>
      )}
      <h3 className="card-title">
        Point {t.pointNumber} · {side === "offense" ? "O line" : "D line"}
      </h3>
      <div className="st-chips">
        {last && (
          <button type="button" className={`st-chip${showing(last) ? " on" : ""}`} onClick={() => act((x) => x.fillDraft(last))}>
            ↺ Last {sideShort[side]} line
          </button>
        )}
        {lines.map((l) => (
          <button key={l.id} type="button" className={`st-chip${showing(l.players) ? " on" : ""}`} onClick={() => act((x) => x.fillDraft(l.players))}>
            <b>{l.side ? sideShort[l.side] : "•"}</b> {l.name}
          </button>
        ))}
      </div>
      {!last && lines.length === 0 && (
        <p className="muted small">
          No {sideShort[side]} lines yet. Pick {lineSize} below.
        </p>
      )}
      <div className="home-actions">
        <button type="button" className="text-btn" onClick={onLines}>
          Set up lines
        </button>
        {t.draftReady && !lines.some((l) => showing(l.players)) && (
          <button type="button" className="text-btn" onClick={onSave}>
            Save as line
          </button>
        )}
        {picked.size > 0 && (
          <button type="button" className="text-btn" onClick={() => act((x) => x.clearDraft())}>
            Clear
          </button>
        )}
      </div>
      <PlayerChooser players={t.available} selected={picked} onToggle={(id) => act((x) => x.toggleDraft(id))} />
    </div>
  );
}

function StartBar({ t, onStart }: { t: GameTracker; onStart: () => void }) {
  const count = t.draft.size;
  const pull = t.nextSide === "defense";
  return (
    <div className="st-row">
      <b className={t.draftReady ? "st-pos st-count" : "st-count"}>
        {count}/{lineSize}
      </b>
      <button type="button" className="btn btn-primary st-big" disabled={!t.draftReady} onClick={onStart}>
        {!t.draftReady ? `Pick ${lineSize - count} more` : pull ? "Start point & pull" : "Start point"}
      </button>
    </div>
  );
}

function LineBar({ t, onChange, onSub }: { t: GameTracker; onChange: () => void; onSub: () => void }) {
  const point = t.currentPoint!;
  const line = new Set(point.line);
  const name = t.savedLines.find((l) => [...line].every((id) => l.players.includes(id)))?.name;
  const subs = point.actions.filter((a) => a.kind === "sub").length;
  return (
    <div className="st-row st-linebar">
      <b>
        {name ?? "Custom line"}
        {subs > 0 ? ` · ${subs} sub${subs > 1 ? "s" : ""}` : ""}
      </b>
      {point.actions.length === 0 ? (
        <button type="button" className="text-btn" onClick={onChange}>
          Change line
        </button>
      ) : (
        <button type="button" className="text-btn" disabled={t.bench.length === 0} onClick={onSub}>
          Sub
        </button>
      )}
    </div>
  );
}

function StatusBanner({ t }: { t: GameTracker }) {
  const armed = t.armed;
  if (armed) {
    const text: Partial<Record<StatKind, string>> = {
      goal: "Score! Tap who caught it in the endzone",
      drop: "Tap who dropped it",
      handBlock: "Tap who got the hand block (+2)",
      breakup: "Tap who got the D (+1)",
      beat: "Tap who got beat (−1)",
    };
    return <p className="st-banner st-armed">{text[armed]}</p>;
  }
  if (t.side === "defense") {
    return <p className="st-banner">{t.canPull ? "We're pulling. Tap Pull to time it." : "On D. Pick a play below, then tap the player."}</p>;
  }
  const h = t.holder;
  const chain = t.passChain;
  return (
    <div>
      <p className="st-banner">{h === null ? "On O. Tap who picked up the disc." : `${t.nameOf(h)} has it. Tap who caught the pass.`}</p>
      {chain.length > 1 && <p className="muted small st-chain">{chain.map((id) => t.nameOf(id).split(" ")[0]).join("  →  ")}</p>}
    </div>
  );
}

function PlayerGrid({ t, act }: { t: GameTracker; act: Act }) {
  const idle = t.side === "defense" && t.armed === null;
  return (
    <div className="st-grid">
      {t.onField.map((id, i) => {
        const p = t.player(id);
        const holding = t.holder === id;
        return (
          <button
            key={id}
            type="button"
            className={`st-tile${holding ? " holding" : ""}${idle ? " idle" : ""}`}
            onClick={() => act((x) => x.tapPlayer(id))}
            aria-label={`${p?.name ?? "Player"}${holding ? ", has the disc" : ""} (key ${i + 1})`}
          >
            <kbd className="st-key">{i + 1}</kbd>
            <b>{p?.number == null ? "–" : `#${p.number}`}</b>
            <span>{p?.name ?? "Player"}</span>
          </button>
        );
      })}
    </div>
  );
}

function ArmButton({ t, act, kind, label, tone, enabled = true, filled = false }: { t: GameTracker; act: Act; kind: StatKind; label: string; tone: "good" | "bad"; enabled?: boolean; filled?: boolean }) {
  const armed = t.armed === kind;
  return (
    <button
      type="button"
      className={`btn st-big st-${tone}${armed ? " armed" : ""}${filled || armed ? " solid" : ""}`}
      aria-pressed={armed}
      disabled={!enabled}
      onClick={() => act((x) => x.arm(kind))}
    >
      {armed ? `${label}…` : label}
    </button>
  );
}

function OffenseActions({ t, act }: { t: GameTracker; act: Act }) {
  const hasDisc = t.holder !== null;
  return (
    <div className="st-row">
      <ArmButton t={t} act={act} kind="goal" label="Score (G)" tone="good" enabled={t.canScore} filled />
      <button type="button" className="btn st-big st-bad" disabled={!hasDisc} onClick={() => act((x) => x.throwaway())}>
        Throwaway (T)
      </button>
      <ArmButton t={t} act={act} kind="drop" label="Drop (X)" tone="bad" enabled={hasDisc} />
    </div>
  );
}

function DefenseActions({ t, act, onPull }: { t: GameTracker; act: Act; onPull: () => void }) {
  return (
    <div className="stack">
      {t.canPull && (
        <button type="button" className="btn btn-primary st-big" onClick={onPull}>
          Pull (P)
        </button>
      )}
      <div className="st-row">
        <ArmButton t={t} act={act} kind="breakup" label="D +1 (B)" tone="good" />
        <ArmButton t={t} act={act} kind="handBlock" label="Hand block +2 (H)" tone="good" />
        <ArmButton t={t} act={act} kind="beat" label="Got beat −1 (N)" tone="bad" />
      </div>
      <div className="st-row">
        <button type="button" className="btn st-big" onClick={() => act((x) => x.weGotIt())}>
          Their turnover (W)
        </button>
        <button type="button" className="btn st-big st-bad solid" onClick={() => act((x) => x.theyScored())}>
          They scored (O)
        </button>
      </div>
    </div>
  );
}

function UndoBar({ t, act }: { t: GameTracker; act: Act }) {
  const label = t.undoLabel;
  return (
    <div className="st-row st-undo">
      <span className="muted small st-ellipsis">{label ? `Last: ${label}` : "Nothing to undo"}</span>
      <button type="button" className="btn btn-small" disabled={!t.canUndo} onClick={() => act((x) => x.undo())}>
        ↶ Undo last (U)
      </button>
    </div>
  );
}

// ---- Lines ----------------------------------------------------------------------------------

function LinesTab({ t, act }: { t: GameTracker; act: Act }) {
  const [editing, setEditing] = useState<StatLine | "new" | null>(null);
  const [importing, setImporting] = useState(false);
  const [note, setNote] = useState("");
  const lines = (["offense", "defense", null] as Array<StatSide | null>).flatMap((s) => t.savedLines.filter((l) => l.side === s));
  const fromEvent = t.eventLinesToImport;
  const sources = t.lineSources;
  const tooFew = t.available.length < lineSize;
  const imported = (n: number) => setNote(n === 0 ? "Nothing new to import" : `Imported ${n} line${n === 1 ? "" : "s"}`);
  const event = t.game.eventId;
  return (
    <div className="stack">
      <p className="muted small">{t.tournament ? `Lines for ${t.tournament.name}, shared by every game in it.` : "Lines for this game."}</p>
      {t.canEdit && (
        <div className="home-actions">
          <button type="button" className="btn btn-primary btn-small" disabled={tooFew} onClick={() => setEditing("new")}>
            New line
          </button>
          {sources.length > 0 && (
            <button type="button" className="btn btn-small" onClick={() => setImporting(!importing)}>
              Import lines
            </button>
          )}
        </div>
      )}
      {note && <p className="form-ok small">{note}</p>}
      {importing && (
        <div className="card st-subcard">
          <h3 className="card-title">Import lines from</h3>
          <ul className="st-plain">
            {sources.map((s) => (
              <li key={s.id}>
                <button
                  type="button"
                  className="text-btn"
                  onClick={() => {
                    let n = 0;
                    act((x) => (n = x.importLines(s.lines)));
                    imported(n);
                    setImporting(false);
                  }}
                >
                  {s.name}
                </button>
                <small className="muted">
                  {event && s.eventId === event ? "Same event · " : ""}
                  {s.lines.map((l) => l.name).join(", ")}
                </small>
              </li>
            ))}
          </ul>
        </div>
      )}
      {t.canEdit && fromEvent.length > 0 && (
        <div className="card st-row">
          <span>
            <b>
              {fromEvent.length} line{fromEvent.length === 1 ? "" : "s"} from the linked event
            </b>
            <small className="muted"> {fromEvent.map((l) => l.name).join(", ")}</small>
          </span>
          <button
            type="button"
            className="btn btn-small"
            onClick={() => {
              let n = 0;
              act((x) => (n = x.importLines(fromEvent)));
              imported(n);
            }}
          >
            Import
          </button>
        </div>
      )}
      {editing && (
        <LinePicker
          title={editing === "new" ? "New line" : `Edit ${editing.name}`}
          available={t.available}
          initial={editing === "new" ? [] : editing.players}
          requireName
          defaultName={editing === "new" ? "" : editing.name}
          defaultSide={editing === "new" ? null : editing.side}
          onDone={(c) => {
            const was = editing;
            setEditing(null);
            if (c) act((x) => x.saveLine(c.saveAs ?? (was === "new" ? "Line" : was.name), c.players, { id: was === "new" ? undefined : was.id, side: c.side }));
          }}
        />
      )}
      {lines.length === 0 ? (
        <p className="empty">No lines yet. Build O and D lines here and they show up when you pick the line for each point.</p>
      ) : (
        <ul className="game-list">
          {lines.map((l) => (
            <li key={l.id} className="card st-row">
              <span>
                <b>
                  {l.side ? `${sideShort[l.side]} · ` : ""}
                  {l.name}
                </b>
                <small className="muted"> {l.players.map((id) => t.nameOf(id)).join(", ")}</small>
              </span>
              {t.canEdit && (
                <span>
                  <button type="button" className="text-btn" onClick={() => setEditing(l)}>
                    Edit
                  </button>
                  <button type="button" className="text-btn st-danger" onClick={() => act((x) => x.deleteLine(l.id))}>
                    Delete
                  </button>
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

// ---- Point log --------------------------------------------------------------------------------

const playTag: Record<StatKind, [string, string]> = {
  pull: ["PULL", "st-tag-pull"],
  pickup: ["PICKUP", "st-tag-muted"],
  catch_: ["CATCH", "st-tag-catch"],
  goal: ["GOAL", "st-tag-goal"],
  throwaway: ["THROWAWAY", "st-tag-bad"],
  drop: ["DROP", "st-tag-bad"],
  handBlock: ["HAND BLOCK", "st-tag-d"],
  breakup: ["BLOCK", "st-tag-d"],
  beat: ["BEAT", "st-tag-beat"],
  theirTurnover: ["THEIR TURN", "st-tag-d"],
  sub: ["SUB", "st-tag-muted"],
};

/** Every point, newest first, with plays, possession changes, timeouts and halftime (_PointLog). */
function PointLog({ t }: { t: GameTracker }) {
  const g = t.game;
  const points = g.points;
  if (points.length === 0 && g.timeouts.length === 0) return <p className="empty">No points yet. Each point is logged here as you track it.</p>;
  let us = 0;
  let them = 0;
  const scores = points.map((p) => {
    if (p.result === "weScored") us++;
    if (p.result === "theyScored") them++;
    return `${us}–${them}`;
  });
  const half = halftimePoint(g);
  const pending = g.timeouts.filter((x) => x.point >= points.length);
  const timeoutRow = (ours: boolean, h: number, key: string) => (
    <li key={key} className="st-play">
      <span className="st-tag st-tag-timeout">TIMEOUT</span>
      <span>
        {ours ? "We" : g.opponent} called timeout · {halfName(h)}
      </span>
    </li>
  );
  return (
    <div className="stack">
      {pending.length > 0 && <ul className="st-plays">{[...pending].reverse().map((x, i) => timeoutRow(x.ours, x.half, `p${i}`))}</ul>}
      {points
        .map((p, i) => ({ p, i }))
        .reverse()
        .map(({ p, i }) => {
          const [label, tone] =
            p.result === "weScored" ? (p.startedOn === "defense" ? ["Break", "st-pos"] : ["Score", "st-pos"]) : p.result === "theyScored" ? ["Opp score", "st-neg"] : ["In play", "st-live"];
          const passes = p.actions.filter((a) => a.kind === "catch_").length;
          const turns = p.actions.filter(turnsOver).length;
          const timeouts = g.timeouts.filter((x) => x.point === i);
          const rows: React.ReactNode[] = [];
          let side = p.startedOn;
          const addTimeouts = (at: number) => timeouts.forEach((x, k) => x.action === at && rows.push(timeoutRow(x.ours, x.half, `t${at}-${k}`)));
          p.actions.forEach((a: StatAction, k) => {
            addTimeouts(k);
            let [tag, cls] = playTag[a.kind];
            if (a.kind === "goal" && p.startedOn === "defense") tag = "BREAK";
            rows.push(
              <li key={`a${k}`} className="st-play">
                <span className={`st-tag ${cls}`}>{tag}</span>
                <span>{t.describe(a)}</span>
              </li>,
            );
            if (turnsOver(a)) {
              side = side === "offense" ? "defense" : "offense";
              rows.push(
                <li key={`s${k}`} className="st-possession muted small">
                  ↳ {side === "offense" ? "Our disc. We're on O." : "Their disc. We're on D."}
                </li>,
              );
            }
          });
          addTimeouts(p.actions.length);
          return (
            <div key={i}>
              {half === i && <p className="st-halftime">HALFTIME · {scores[i]}</p>}
              <details className="card st-point" open={i === points.length - 1}>
                <summary>
                  <span className={`st-side st-side-${p.startedOn}`}>{sideShort[p.startedOn]}</span>
                  <span>
                    <b>
                      Point {i + 1} · {p.startedOn === "offense" ? "O line" : "D line"}
                    </b>
                    <small>
                      <span className={tone}>{label}</span>
                      {p.line.length > 0 && ` · ${passes} pass${passes === 1 ? "" : "es"} · ${turns} turn${turns === 1 ? "" : "s"}`}
                      {timeouts.length > 0 && ` · ${timeouts.length} timeout${timeouts.length === 1 ? "" : "s"}`}
                    </small>
                  </span>
                  <b className="st-score">{scores[i]}</b>
                </summary>
                {p.line.length > 0 && <p className="muted small">{[...played(p)].map((id) => t.nameOf(id)).join(", ")}</p>}
                {rows.length === 0 ? <p className="muted small">{p.line.length === 0 ? "Score only, no stats" : "No stats recorded"}</p> : <ul className="st-plays">{rows}</ul>}
              </details>
            </div>
          );
        })}
    </div>
  );
}
