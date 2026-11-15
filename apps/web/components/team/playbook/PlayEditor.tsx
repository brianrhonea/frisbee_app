"use client";
import {
  type FieldPoint,
  pathIn,
  type PlayArrow,
  type PlayCategory,
  playCategories,
  playCategoryLabels,
  type PlayDoc,
  type PlayElement,
  type PlayElementKind,
  playLimits,
  type PlayStep,
  positionsAfter,
  positionsAt,
} from "@stall10/shared";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "../../AuthProvider";
import { type FieldHit, PlayField } from "./PlayField";

type Tool = "select" | PlayElementKind | "cut" | "throw_" | "erase";
const tools: Array<[Tool, string, string]> = [
  ["select", "Move", "Drag pieces. In a step, dragging records where they go."],
  ["offense", "Offense", "Click the field to add an offensive player."],
  ["defense", "Defense", "Click the field to add a defender."],
  ["disc", "Disc", "Click to place the disc."],
  ["cone", "Cone", "Click to place a cone."],
  ["cut", "Cut", "Drag to draw a cut."],
  ["throw_", "Throw", "Drag to draw a throw (drawn straight)."],
  ["erase", "Erase", "Click a piece or arrow to remove it; in a step, its movement."],
];
const stepTools: Tool[] = ["select", "erase"];

interface Snapshot {
  elements: PlayElement[];
  arrows: PlayArrow[];
  steps: PlayStep[];
}

const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2));
const far = (a: FieldPoint, b: FieldPoint) => (a.x - b.x) ** 2 + (a.y - b.y) ** 2 >= 0.0004;

/** The next free number for a new player of [kind] (_nextLabel). */
function nextLabel(elements: PlayElement[], kind: PlayElementKind): string {
  if (kind !== "offense" && kind !== "defense") return "";
  const used = new Set(elements.filter((e) => e.kind === kind).map((e) => Number.parseInt(e.label, 10)));
  let n = 1;
  while (used.has(n)) n++;
  return String(n);
}

/** Plays a play's steps in order, one a second and a bit, easing each. */
function usePlayback(play: Pick<PlayDoc, "elements" | "steps">) {
  const [t, setT] = useState<number | null>(null);
  const frame = useRef(0);
  const steps = play.steps?.length ?? 0;
  const stop = useCallback(() => {
    cancelAnimationFrame(frame.current);
    setT(null);
  }, []);
  const start = useCallback(() => {
    cancelAnimationFrame(frame.current);
    const began = performance.now();
    const tick = (now: number) => {
      const next = (now - began) / 1200;
      if (next >= steps + 0.5) {
        setT(null);
        return;
      }
      setT(Math.min(next, steps));
      frame.current = requestAnimationFrame(tick);
    };
    frame.current = requestAnimationFrame(tick);
  }, [steps]);
  useEffect(() => () => cancelAnimationFrame(frame.current), []);
  return { t, start, stop, positions: t === null ? null : positionsAt(play, t), step: t === null ? null : Math.min(Math.floor(t), steps - 1) };
}

/**
 * Draws and edits a play like the app's play editor: pieces and arrows on
 * the setup, then steps where dragging a piece records its path, with
 * undo, playback and the play's name, kind and notes. Saves through the
 * API (`/v1/teams/:id/plays`).
 */
export function PlayEditor({ teamId, id, initial }: { teamId: string; id: string | null; initial?: PlayDoc }) {
  const { user } = useAuth();
  const router = useRouter();
  const [name, setName] = useState(initial?.name ?? "");
  const [category, setCategory] = useState<PlayCategory>(initial?.category ?? "offense");
  const [notes, setNotes] = useState(initial?.notes ?? "");
  const [play, setPlay] = useState<Snapshot>({ elements: initial?.elements ?? [], arrows: initial?.arrows ?? [], steps: initial?.steps ?? [] });
  const [past, setPast] = useState<Snapshot[]>([]);
  const [future, setFuture] = useState<Snapshot[]>([]);
  const [tool, setTool] = useState<Tool>("select");
  const [step, setStep] = useState(0);
  const [selected, setSelected] = useState<string | null>(null);
  const [drawing, setDrawing] = useState<FieldPoint[] | null>(null);
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const drag = useRef<{ id: string } | null>(null);
  const playback = usePlayback(play);
  const setup = step === 0;

  // Leaving with unsaved changes asks first.
  useEffect(() => {
    if (!dirty) return;
    const warn = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);

  function change(next: Snapshot) {
    setPast((p) => [...p.slice(-49), play]);
    setFuture([]);
    setPlay(next);
    setDirty(true);
  }
  const undo = () => {
    const prev = past[past.length - 1];
    if (!prev) return;
    setPast(past.slice(0, -1));
    setFuture([play, ...future]);
    setPlay(prev);
    setDirty(true);
  };
  const redo = () => {
    const next = future[0];
    if (!next) return;
    setFuture(future.slice(1));
    setPast([...past, play]);
    setPlay(next);
    setDirty(true);
  };

  function remove(id: string) {
    if (!setup) {
      // In a step, erasing takes back that piece's movement.
      const s = play.steps[step - 1]!;
      if (!s.paths[id]) return;
      const paths = { ...s.paths };
      delete paths[id];
      change({ ...play, steps: play.steps.map((x, i) => (i === step - 1 ? { ...x, paths } : x)) });
      return;
    }
    change({
      elements: play.elements.filter((e) => e.id !== id),
      arrows: play.arrows.filter((a) => a.id !== id),
      steps: play.steps.map((s) => {
        const paths = { ...s.paths };
        delete paths[id];
        return { ...s, paths };
      }),
    });
    if (selected === id) setSelected(null);
  }

  /** In a step, a drag of [id] to [p] extends its path there (_recordPoint). */
  function record(snapshot: Snapshot, id: string, p: FieldPoint): Snapshot {
    const index = step - 1;
    const s = snapshot.steps[index]!;
    const disc = snapshot.elements.find((e) => e.id === id)?.kind === "disc";
    let path = [...(s.paths[id] ?? [])];
    if (disc) path = [p];
    else {
      const prev = path.length >= 2 ? path[path.length - 2]! : (positionsAfter(snapshot, index)[id] ?? p);
      if (path.length > 0 && !far(p, prev)) path[path.length - 1] = p;
      else path.push(p);
      if (path.length > playLimits.pathPoints) path = path.filter((_, i) => i % 2 === 0 || i === path.length - 1);
    }
    return { ...snapshot, steps: snapshot.steps.map((x, i) => (i === index ? { ...x, paths: { ...x.paths, [id]: path } } : x)) };
  }

  function onDown(h: FieldHit) {
    if (playback.t !== null) playback.stop();
    setError(null);
    if (tool === "erase") {
      if (h.kind !== "field") remove(h.id);
      return;
    }
    if (tool === "cut" || tool === "throw_") {
      if (setup && play.arrows.length < playLimits.arrows) setDrawing([h.at]);
      return;
    }
    if (tool === "select") {
      if (h.kind === "element") {
        setSelected(h.id);
        // One drag is one undo step.
        setPast((p) => [...p.slice(-49), play]);
        setFuture([]);
        drag.current = { id: h.id };
      } else setSelected(h.kind === "arrow" ? h.id : null);
      return;
    }
    // Placing a piece (the setup only).
    if (!setup || play.elements.length >= playLimits.elements) return;
    const el: PlayElement = { id: uid(), kind: tool, position: h.at, label: nextLabel(play.elements, tool) };
    change({ ...play, elements: [...play.elements, el] });
  }
  function onMove(at: FieldPoint) {
    if (drawing) {
      const last = drawing[drawing.length - 1]!;
      if ((at.x - last.x) ** 2 + (at.y - last.y) ** 2 > 0.00008 && drawing.length < playLimits.arrowPoints) setDrawing([...drawing, at]);
      return;
    }
    const d = drag.current;
    if (!d) return;
    setPlay((cur) => (setup ? { ...cur, elements: cur.elements.map((e) => (e.id === d.id ? { ...e, position: at } : e)) } : record(cur, d.id, at)));
    setDirty(true);
  }
  function onUp(at: FieldPoint) {
    drag.current = null;
    if (!drawing) return;
    const pts = [...drawing, at];
    setDrawing(null);
    const kind = tool === "throw_" ? "throw_" : "cut";
    if (!far(pts[0]!, pts[pts.length - 1]!)) return;
    const points = kind === "throw_" ? [pts[0]!, pts[pts.length - 1]!] : pts;
    change({ ...play, arrows: [...play.arrows, { id: uid(), kind, points }] });
  }

  // Keys: Delete removes the selection, Ctrl/Cmd+Z undoes, Shift too redoes.
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      const typing = (e.target as HTMLElement)?.closest?.("input, textarea, select");
      if (typing) return;
      if ((e.key === "Delete" || e.key === "Backspace") && selected) {
        e.preventDefault();
        remove(selected);
      } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
        e.preventDefault();
        if (e.shiftKey) redo();
        else undo();
      }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  });

  async function save() {
    if (!user) return;
    if (!name.trim()) return setError("Name the play.");
    setBusy(true);
    setError(null);
    try {
      const body = { name: name.trim(), category, notes, elements: play.elements, arrows: play.arrows, steps: play.steps };
      const base = `/v1/teams/${encodeURIComponent(teamId)}/plays`;
      if (id) await callApi(user, `${base}/${encodeURIComponent(id)}`, { method: "PUT", body });
      else {
        const r = await callApi<{ id: string }>(user, base, { method: "POST", body });
        setDirty(false);
        router.replace(`/teams/${encodeURIComponent(teamId)}/plays/${encodeURIComponent(r.id)}`);
        return;
      }
      setDirty(false);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function destroy() {
    if (!user || !id || !window.confirm(`Delete ${name || "this play"}?`)) return;
    setBusy(true);
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/plays/${encodeURIComponent(id)}`, { method: "DELETE" });
      setDirty(false);
      router.push(`/teams/${encodeURIComponent(teamId)}/more?tab=playbook`);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  const shown = playback.positions ?? (setup ? undefined : positionsAfter(play, step));
  const trails =
    playback.t === null && !setup
      ? Object.keys(play.steps[step - 1]?.paths ?? {}).map((eid) => ({
          id: eid,
          points: pathIn(play, step - 1, eid),
          disc: play.elements.find((e) => e.id === eid)?.kind === "disc",
        }))
      : undefined;
  const caption = playback.step !== null ? play.steps[playback.step]?.note : null;
  const active = setup ? tool : stepTools.includes(tool) ? tool : "select";

  return (
    <div className="play-editor">
      <div className="card play-editor-main">
        <div className="play-tools" role="toolbar" aria-label="Tools">
          {tools.map(([t, label, hint]) => (
            <button
              key={t}
              type="button"
              className={`play-tool${active === t ? " on" : ""}`}
              aria-pressed={active === t}
              title={hint}
              disabled={!setup && !stepTools.includes(t)}
              onClick={() => setTool(t)}
            >
              <span className={`play-tool-icon ${t}`} aria-hidden="true" />
              {label}
            </button>
          ))}
          <span className="play-tools-gap" />
          <button type="button" className="text-btn" disabled={past.length === 0} onClick={undo} title="Undo (Ctrl+Z)">
            Undo
          </button>
          <button type="button" className="text-btn" disabled={future.length === 0} onClick={redo} title="Redo (Ctrl+Shift+Z)">
            Redo
          </button>
        </div>
        <p className="muted small play-hint">{tools.find(([t]) => t === active)?.[2]}</p>
        <PlayField
          elements={play.elements}
          arrows={setup || playback.t !== null ? play.arrows : []}
          positions={shown}
          trails={trails}
          ghost={drawing ? { kind: tool === "throw_" ? "throw_" : "cut", points: drawing } : null}
          selected={selected}
          label={`${name || "Play"} diagram`}
          handlers={playback.t === null ? { onDown, onMove, onUp } : undefined}
        />
        {caption && <p className="play-caption">{caption}</p>}

        <div className="play-steps" role="tablist" aria-label="Steps">
          <button type="button" role="tab" aria-selected={setup} className={`play-step${setup ? " on" : ""}`} onClick={() => { playback.stop(); setStep(0); setSelected(null); }}>
            Setup
          </button>
          {play.steps.map((s, i) => (
            <button key={s.id} type="button" role="tab" aria-selected={step === i + 1} className={`play-step${step === i + 1 ? " on" : ""}`} onClick={() => { playback.stop(); setStep(i + 1); setSelected(null); }}>
              Step {i + 1}
            </button>
          ))}
          <button
            type="button"
            className="btn btn-small"
            disabled={play.steps.length >= playLimits.steps || play.elements.length === 0}
            onClick={() => {
              change({ ...play, steps: [...play.steps, { id: uid(), note: "", paths: {} }] });
              setStep(play.steps.length + 1);
              setTool("select");
            }}
          >
            Add step
          </button>
          {play.steps.length > 0 && (
            <button type="button" className="btn btn-small" onClick={() => (playback.t === null ? playback.start() : playback.stop())}>
              {playback.t === null ? "▶ Play" : "■ Stop"}
            </button>
          )}
        </div>
        {!setup && (
          <div className="play-step-edit">
            <label>
              Step {step} caption
              <input
                value={play.steps[step - 1]?.note ?? ""}
                maxLength={playLimits.stepNote}
                placeholder="e.g. Break-side swing"
                onChange={(e) => {
                  setPlay({ ...play, steps: play.steps.map((s, i) => (i === step - 1 ? { ...s, note: e.target.value } : s)) });
                  setDirty(true);
                }}
              />
            </label>
            <button
              type="button"
              className="text-btn danger"
              onClick={() => {
                change({ ...play, steps: play.steps.filter((_, i) => i !== step - 1) });
                setStep(step - 1);
              }}
            >
              Delete step
            </button>
          </div>
        )}
      </div>

      <aside className="card settings-form play-details">
        <h2 className="card-title">{id ? "Edit play" : "New play"}</h2>
        <label>
          Name
          <input value={name} maxLength={playLimits.name} onChange={(e) => { setName(e.target.value); setDirty(true); }} />
        </label>
        <label>
          Kind
          <select value={category} onChange={(e) => { setCategory(e.target.value as PlayCategory); setDirty(true); }}>
            {playCategories.map((c) => (
              <option key={c} value={c}>
                {playCategoryLabels[c]}
              </option>
            ))}
          </select>
        </label>
        <label>
          Notes
          <textarea rows={5} value={notes} maxLength={playLimits.notes} onChange={(e) => { setNotes(e.target.value); setDirty(true); }} />
        </label>
        <div className="home-actions">
          <button type="button" className="btn btn-primary btn-small" disabled={busy || !dirty} onClick={() => void save()}>
            {busy ? "Saving…" : dirty ? "Save" : "Saved"}
          </button>
          {id && (
            <button type="button" className="btn btn-small btn-danger" disabled={busy} onClick={() => void destroy()}>
              Delete play
            </button>
          )}
          <button
            type="button"
            className="text-btn"
            disabled={play.elements.length === 0 && play.arrows.length === 0}
            onClick={() => {
              if (window.confirm("Clear the whole diagram?")) {
                change({ elements: [], arrows: [], steps: [] });
                setStep(0);
              }
            }}
          >
            Clear diagram
          </button>
        </div>
        {error && <p className="form-error" role="alert">{error}</p>}
      </aside>
    </div>
  );
}

/** A play for every member: the diagram, playback and its notes. */
export function PlayViewer({ play }: { play: PlayDoc }) {
  const playback = usePlayback(play);
  const caption = playback.step !== null ? play.steps?.[playback.step]?.note : null;
  return (
    <div className="card play-viewer">
      <PlayField elements={play.elements ?? []} arrows={play.arrows ?? []} positions={playback.positions ?? undefined} label={`${play.name ?? "Play"} diagram`} />
      {caption && <p className="play-caption">{caption}</p>}
      {(play.steps?.length ?? 0) > 0 && (
        <div className="home-actions">
          <button type="button" className="btn btn-small" onClick={() => (playback.t === null ? playback.start() : playback.stop())}>
            {playback.t === null ? "▶ Play" : "■ Stop"}
          </button>
          <span className="muted small">{play.steps!.length + 1} steps</span>
        </div>
      )}
      {play.notes && <p className="play-notes-full">{play.notes}</p>}
    </div>
  );
}
