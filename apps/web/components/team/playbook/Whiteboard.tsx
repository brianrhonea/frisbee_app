"use client";
import { type DrawingColor, type FieldPoint, type PlayCategory, playCategories, playCategoryLabels, type PlayDoc, playLimits } from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type FormEvent, useEffect, useReducer, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "../../AuthProvider";
import { Dialog } from "../../Dialog";
import { useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { type FieldHit, PlayField } from "./PlayField";
import {
  boardBody,
  defaultWhiteboardName,
  hasUnsaved,
  initialWhiteboard,
  isEmpty,
  strokesFull,
  tokensFull,
  type WhiteboardTool,
  whiteboardReducer,
} from "./whiteboard_state";
import "./whiteboard.css";

const tools: Array<[WhiteboardTool, string, string]> = [
  ["move", "Move", "Drag pieces around."],
  ["pen", "Pen", "Draw on the field."],
  ["offense", "Offense", "Click to drop an offensive player; drag one to move it."],
  ["defense", "Defense", "Click to drop a defender; drag one to move it."],
  ["disc", "Disc", "Click to drop the disc; drag it to move it."],
  ["cone", "Cone", "Click to drop a cone; drag one to move it."],
  ["erase", "Erase", "Click a line or piece to remove it, or drag across lines to wipe them."],
];
const pens: Array<[DrawingColor, string]> = [
  ["white", "White pen"],
  ["ink", "Navy pen"],
  ["turf", "Turf pen"],
  ["amber", "Amber pen"],
];
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2));

/**
 * The playbook's whiteboard (/teams/:id/whiteboards/new, or a saved one's
 * id): a field to sketch a chalk talk on. Every member can sketch; those
 * who manage the team save it as a play or as a whiteboard.
 */
export function WhiteboardPage({ playId }: { playId: string }) {
  const { teamId, kind, viewer } = useTeamHub();
  const isNew = playId === "new";
  const member = viewer.state === "member";
  const doc = useLiveDoc<PlayDoc>(member && !isNew ? `teams/${teamId}/plays/${playId}` : null);
  const playbook = `/teams/${encodeURIComponent(teamId)}/playbook?view=whiteboard`;

  if (kind !== "team") return <p className="empty">Communities don&apos;t have a playbook.</p>;
  if (!member) return <MembersOnlySection what="playbook" />;
  if (isNew) return <WhiteboardBoard teamId={teamId} canSave={viewer.can("manageTeam")} back={playbook} />;
  if (doc.error) return <p className="form-error">{doc.error}</p>;
  if (doc.data === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
  if (doc.data === null)
    return (
      <p className="empty">
        That whiteboard was deleted.{" "}
        <Link href={playbook} className="text-btn">
          ← Playbook
        </Link>
      </p>
    );
  // Keyed by id and read once: later snapshots (our own saves) don't reset the sketch.
  return <WhiteboardBoard key={doc.data.id} teamId={teamId} canSave={viewer.can("manageTeam")} back={playbook} initial={doc.data} />;
}

type Ask = { kind: "play" } | { kind: "whiteboard" } | { kind: "discard"; then: () => void } | null;

function WhiteboardBoard({ teamId, canSave, back, initial }: { teamId: string; canSave: boolean; back: string; initial?: PlayDoc & { id: string } }) {
  const { user } = useAuth();
  const router = useRouter();
  const [s, dispatch] = useReducer(whiteboardReducer, initial, (doc) =>
    doc ? whiteboardReducer(initialWhiteboard, { type: "load", id: doc.id, doc }) : initialWhiteboard,
  );
  // The stroke being drawn: a ref for the pointer handlers (several moves
  // can arrive between renders), state for painting it.
  const [draft, setDraftState] = useState<FieldPoint[] | null>(null);
  const draftRef = useRef<FieldPoint[] | null>(null);
  const setDraft = (d: FieldPoint[] | null) => {
    draftRef.current = d;
    setDraftState(d);
  };
  const [menu, setMenu] = useState(false);
  const [ask, setAsk] = useState<Ask>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<{ text: string; open?: string } | null>(null);
  const gesture = useRef<{ from: FieldPoint; moved: boolean; dragging: string | null; pending: string | null; erasing: boolean } | null>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const unsaved = hasUnsaved(s);
  const base = `/v1/teams/${encodeURIComponent(teamId)}/plays`;

  // Leaving the site with unsaved changes asks the browser's own question.
  useEffect(() => {
    if (!unsaved) return;
    const warn = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [unsaved]);

  // Ctrl/Cmd+Z undoes; Esc closes the save menu (dialogs close themselves).
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape" && menu) {
        setMenu(false);
        return;
      }
      if ((e.target as HTMLElement)?.closest?.("input, textarea, select, dialog")) return;
      if ((e.ctrlKey || e.metaKey) && !e.shiftKey && e.key.toLowerCase() === "z") {
        e.preventDefault();
        dispatch({ type: "undo" });
      }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [menu]);

  // Any other link on the page (hub tabs, the header) asks first too while
  // the sketch has unsaved changes. Browser Back can't be caught.
  useEffect(() => {
    if (!unsaved) return;
    const click = (e: MouseEvent) => {
      if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      const a = (e.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!a || a.target === "_blank" || a.hasAttribute("download")) return;
      const url = new URL(a.href, window.location.href);
      if (url.origin !== window.location.origin || (url.pathname === window.location.pathname && url.search === window.location.search)) return;
      e.preventDefault();
      e.stopPropagation();
      setAsk({ kind: "discard", then: () => router.push(url.pathname + url.search + url.hash) });
    };
    document.addEventListener("click", click, true);
    return () => document.removeEventListener("click", click, true);
  }, [unsaved, router]);

  // A click outside the save menu closes it.
  useEffect(() => {
    if (!menu) return;
    const out = (e: PointerEvent) => {
      if (!menuRef.current?.contains(e.target as Node)) setMenu(false);
    };
    document.addEventListener("pointerdown", out);
    return () => document.removeEventListener("pointerdown", out);
  }, [menu]);

  useEffect(() => {
    if (!toast) return;
    const t = window.setTimeout(() => setToast(null), 6000);
    return () => window.clearTimeout(t);
  }, [toast]);

  // ---- Drawing ---------------------------------------------------------

  const far = (a: FieldPoint, b: FieldPoint) => Math.hypot((a.x - b.x) * 40, (a.y - b.y) * 110) > 0.8;

  function onDown(h: FieldHit) {
    setMenu(false);
    gesture.current = { from: h.at, moved: false, dragging: null, pending: null, erasing: false };
    if (s.tool === "pen") {
      if (!strokesFull(s)) setDraft([h.at]);
      return;
    }
    if (s.tool === "erase") {
      gesture.current.erasing = true;
      if (h.kind === "drawing" || h.kind === "element") dispatch({ type: "erase", id: h.id });
      return;
    }
    // Move and the piece tools pick up a piece under the pointer once it moves.
    if (h.kind === "element") gesture.current.pending = h.id;
  }
  function onMove(at: FieldPoint, drawing: string | null) {
    const g = gesture.current;
    if (!g) return;
    if (!g.moved && far(g.from, at)) g.moved = true;
    const draft = draftRef.current;
    if (draft) {
      const last = draft[draft.length - 1]!;
      const dx = at.x - last.x;
      const dy = at.y - last.y;
      if (dx * dx + dy * dy > 0.0001) setDraft([...draft, at]);
      return;
    }
    if (g.erasing) {
      // Dragging the eraser wipes the lines it crosses (not pieces).
      if (drawing) dispatch({ type: "erase", id: drawing });
      return;
    }
    if (g.pending && g.moved) {
      dispatch({ type: "beginMove", id: g.pending });
      g.dragging = g.pending;
      g.pending = null;
    }
    if (g.dragging) dispatch({ type: "move", id: g.dragging, to: at });
  }
  function onUp(at: FieldPoint) {
    const g = gesture.current;
    gesture.current = null;
    const draft = draftRef.current;
    if (draft) {
      const pts = far(draft[draft.length - 1]!, at) ? [...draft, at] : draft;
      setDraft(null);
      dispatch({ type: "addStroke", id: uid(), points: pts });
      return;
    }
    // A click (no drag) with a piece tool drops a piece where it began.
    if (g && !g.moved && !g.dragging && (s.tool === "offense" || s.tool === "defense" || s.tool === "disc" || s.tool === "cone")) {
      dispatch({ type: "place", id: uid(), at: g.from });
    }
  }

  // ---- Saving and leaving ---------------------------------------------

  async function saveAsPlay(name: string, category: PlayCategory) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      const r = await callApi<{ id: string }>(user, base, { method: "POST", body: boardBody(s, { kind: "play", name, category }) });
      dispatch({ type: "savedPlay" });
      setAsk(null);
      setToast({ text: "Saved as a play", open: `/teams/${encodeURIComponent(teamId)}/plays/${encodeURIComponent(r.id)}` });
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function saveWhiteboard(name: string) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      const body = boardBody(s, { kind: "whiteboard", name });
      let id = s.savedId;
      if (id) await callApi(user, `${base}/${encodeURIComponent(id)}`, { method: "PUT", body });
      else {
        id = (await callApi<{ id: string }>(user, base, { method: "POST", body })).id;
        // The address becomes the saved whiteboard's without reloading the board (undo and all).
        window.history.replaceState(null, "", `/teams/${encodeURIComponent(teamId)}/whiteboards/${encodeURIComponent(id)}`);
      }
      dispatch({ type: "savedWhiteboard", id, name: body.name });
      setAsk(null);
      setToast({ text: "Whiteboard saved" });
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  function pick(what: "play" | "whiteboard") {
    setMenu(false);
    setError(null);
    // A saved whiteboard keeps its name; a new one is named first.
    if (what === "whiteboard" && s.savedId && s.name) void saveWhiteboard(s.name);
    else setAsk({ kind: what });
  }
  /** Leaves for [href], asking first when the sketch has unsaved changes. */
  function leave(href: string) {
    if (unsaved) setAsk({ kind: "discard", then: () => router.push(href) });
    else router.push(href);
  }
  /** A link's click, asking first when the sketch has unsaved changes. */
  const guard = (href: string) => (e: { preventDefault: () => void }) => {
    if (!unsaved) return;
    e.preventDefault();
    leave(href);
  };

  const note = strokesFull(s)
    ? "The whiteboard is full: erase a line to draw another."
    : tokensFull(s)
      ? "That's the most pieces a whiteboard holds."
      : !canSave
        ? "Sketch away. Only the team's admins can save whiteboards."
        : null;
  const hint = tools.find(([t]) => t === s.tool)?.[2];

  return (
    <div className="stack whiteboard">
      <Link href={back} className="text-btn" onClick={guard(back)}>
        ← Playbook
      </Link>
      <div className="card wb-main">
        <div className="wb-head">
          <div className="wb-title">
            <h2 className="card-title">{s.name || "Whiteboard"}</h2>
            <p className="muted small">{s.savedId === null ? "Not saved" : s.dirty ? "Unsaved changes" : "Saved whiteboard"}</p>
          </div>
          <div className="wb-actions">
            <button type="button" className="btn btn-quiet btn-small" onClick={() => leave(back)}>
              Discard
            </button>
            {canSave && (
              <div className="wb-save" ref={menuRef}>
                <button
                  type="button"
                  className="btn btn-primary btn-small"
                  aria-haspopup="menu"
                  aria-expanded={menu}
                  disabled={isEmpty(s) || busy}
                  onClick={() => setMenu(!menu)}
                >
                  {busy ? "Saving…" : "Save"}
                </button>
                {menu && (
                  <div className="menu-list" role="menu">
                    <button type="button" role="menuitem" onClick={() => pick("play")}>
                      Save as play
                    </button>
                    <button type="button" role="menuitem" onClick={() => pick("whiteboard")}>
                      Save whiteboard
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        <div className="play-tools" role="toolbar" aria-label="Tools">
          {tools.map(([t, label, tip]) => (
            <button key={t} type="button" className={`play-tool${s.tool === t ? " on" : ""}`} aria-pressed={s.tool === t} title={tip} onClick={() => dispatch({ type: "tool", tool: t })}>
              <span className={`play-tool-icon wb-icon-${t}${t === "pen" ? ` ${s.color}` : ""} ${t}`} aria-hidden="true" />
              {label}
            </button>
          ))}
        </div>
        <p className="muted small play-hint">{hint}</p>
        <PlayField
          className={`wb-field tool-${s.tool}`}
          elements={s.tokens}
          arrows={[]}
          drawings={s.strokes}
          draft={draft ? { color: s.color, points: draft } : null}
          label={`${s.name || "Whiteboard"} sketch`}
          handlers={{ onDown, onMove, onUp }}
        />
        {note && <p className="muted small wb-note">{note}</p>}
        <div className="wb-pens">
          <div className="wb-colors" role="group" aria-label="Pen colour">
            {pens.map(([c, label]) => {
              const on = s.tool === "pen" && s.color === c;
              return (
                <button key={c} type="button" className={`wb-dot ${c}${on ? " on" : ""}`} aria-pressed={on} aria-label={label} title={label} onClick={() => dispatch({ type: "color", color: c })} />
              );
            })}
          </div>
          <span className="play-tools-gap" />
          <button type="button" className="text-btn" disabled={s.history.length === 0} onClick={() => dispatch({ type: "undo" })} title="Undo (Ctrl+Z)">
            Undo
          </button>
          <button type="button" className="text-btn" disabled={isEmpty(s)} onClick={() => dispatch({ type: "clear" })} title="Clear whiteboard">
            Clear
          </button>
        </div>
        {error && !ask && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
      </div>

      {toast && (
        <div className="wb-toast" role="status">
          <span>{toast.text}</span>
          {toast.open && (
            <Link href={toast.open} className="text-btn" onClick={guard(toast.open)}>
              Open
            </Link>
          )}
        </div>
      )}

      {ask?.kind === "play" && <SaveAsPlayDialog initialName={s.name} busy={busy} error={error} onCancel={() => setAsk(null)} onSave={(n, c) => void saveAsPlay(n, c)} />}
      {ask?.kind === "whiteboard" && <NameDialog initialName={defaultWhiteboardName(new Date())} busy={busy} error={error} onCancel={() => setAsk(null)} onSave={(n) => void saveWhiteboard(n)} />}
      {ask?.kind === "discard" && (
        <Dialog label="Discard sketch?" onClose={() => setAsk(null)} className="card wb-dialog" dismissOnBackdrop>
          <h2 className="card-title">Discard sketch?</h2>
          <p className="muted">What you drew on the whiteboard won&apos;t be kept.</p>
          <div className="form-actions">
            <button type="button" className="btn btn-quiet btn-small" onClick={() => setAsk(null)}>
              Cancel
            </button>
            <button
              type="button"
              className="btn btn-ink btn-small"
              onClick={() => {
                const then = ask.then;
                setAsk(null);
                then();
              }}
            >
              Discard
            </button>
          </div>
        </Dialog>
      )}
    </div>
  );
}

function SaveAsPlayDialog({
  initialName,
  busy,
  error,
  onCancel,
  onSave,
}: {
  initialName: string;
  busy: boolean;
  error: string | null;
  onCancel: () => void;
  onSave: (name: string, category: PlayCategory) => void;
}) {
  const [name, setName] = useState(initialName);
  const [category, setCategory] = useState<PlayCategory>("offense");
  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (name.trim()) onSave(name, category);
  };
  return (
    <Dialog label="Save as play" onClose={() => !busy && onCancel()} className="card wb-dialog">
      <form className="settings-form" onSubmit={submit}>
        <h2 className="card-title">Save as play</h2>
        <label>
          Play name
          <input autoFocus value={name} maxLength={playLimits.name} onChange={(e) => setName(e.target.value)} />
        </label>
        <label>
          Category
          <select value={category} onChange={(e) => setCategory(e.target.value as PlayCategory)}>
            {playCategories.map((c) => (
              <option key={c} value={c}>
                {playCategoryLabels[c]}
              </option>
            ))}
          </select>
        </label>
        <p className="muted small">The pieces become the play&apos;s setup and your lines are kept. Add steps in the play editor.</p>
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <div className="form-actions">
          <button type="button" className="btn btn-quiet btn-small" disabled={busy} onClick={onCancel}>
            Cancel
          </button>
          <button type="submit" className="btn btn-primary btn-small" disabled={busy || !name.trim()}>
            {busy ? "Saving…" : "Save"}
          </button>
        </div>
      </form>
    </Dialog>
  );
}

function NameDialog({
  initialName,
  busy,
  error,
  onCancel,
  onSave,
}: {
  initialName: string;
  busy: boolean;
  error: string | null;
  onCancel: () => void;
  onSave: (name: string) => void;
}) {
  const [name, setName] = useState(initialName);
  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (name.trim()) onSave(name);
  };
  return (
    <Dialog label="Save whiteboard" onClose={() => !busy && onCancel()} className="card wb-dialog">
      <form className="settings-form" onSubmit={submit}>
        <h2 className="card-title">Save whiteboard</h2>
        <label>
          Name
          <input autoFocus value={name} maxLength={playLimits.name} onChange={(e) => setName(e.target.value)} />
        </label>
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
        <div className="form-actions">
          <button type="button" className="btn btn-quiet btn-small" disabled={busy} onClick={onCancel}>
            Cancel
          </button>
          <button type="submit" className="btn btn-primary btn-small" disabled={busy || !name.trim()}>
            {busy ? "Saving…" : "Save"}
          </button>
        </div>
      </form>
    </Dialog>
  );
}
