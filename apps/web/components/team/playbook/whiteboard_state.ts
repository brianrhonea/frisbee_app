// The playbook whiteboard's state and the pen strokes' geometry, as plain
// TypeScript (no React) so the rules sit in one place: a reducer that
// mirrors the app's WhiteboardViewModel, and the hit test and smoothing
// FieldGeometry / FieldPainter use. The website has no unit-test runner;
// these were checked against the app's whiteboard_viewmodel_test cases.
import {
  type DrawingColor,
  type FieldPoint,
  fieldYards,
  type PlayDoc,
  type PlayDrawing,
  type PlayElement,
  type PlayElementKind,
  playLimits,
} from "@stall10/shared";

export type WhiteboardTool = "move" | "pen" | PlayElementKind | "erase";

/** What the board holds: pen strokes and pieces. */
export interface Board {
  strokes: PlayDrawing[];
  tokens: PlayElement[];
}

export interface WhiteboardState extends Board {
  tool: WhiteboardTool;
  color: DrawingColor;
  /** Earlier boards, newest last (at most [maxHistory]). */
  history: Board[];
  /** Changed since it was opened or last saved. */
  dirty: boolean;
  /** The saved whiteboard this sketch updates, once there is one. */
  savedId: string | null;
  /** The saved whiteboard's name; empty until saved. */
  name: string;
}

export const maxHistory = 100;

export type WhiteboardAction =
  | { type: "load"; id: string; doc: PlayDoc }
  | { type: "tool"; tool: WhiteboardTool }
  | { type: "color"; color: DrawingColor }
  | { type: "addStroke"; id: string; points: FieldPoint[] }
  | { type: "place"; id: string; at: FieldPoint }
  | { type: "beginMove"; id: string }
  | { type: "move"; id: string; to: FieldPoint }
  | { type: "erase"; id: string }
  | { type: "clear" }
  | { type: "undo" }
  | { type: "savedPlay" }
  | { type: "savedWhiteboard"; id: string; name: string };

export const initialWhiteboard: WhiteboardState = {
  strokes: [],
  tokens: [],
  tool: "pen",
  color: "white",
  history: [],
  dirty: false,
  savedId: null,
  name: "",
};

export const isEmpty = (s: Board) => s.strokes.length === 0 && s.tokens.length === 0;
export const strokesFull = (s: Board) => s.strokes.length >= playLimits.drawings;
export const tokensFull = (s: Board) => s.tokens.length >= playLimits.elements;
/** Whether leaving asks "Discard sketch?": changes not saved, and not a blank board drawn on and then wiped. */
export const hasUnsaved = (s: WhiteboardState) => s.dirty && !(s.savedId === null && isEmpty(s));

const clamp = (v: number) => Math.min(1, Math.max(0, v));
const clampPoint = (p: FieldPoint): FieldPoint => ({ x: clamp(p.x), y: clamp(p.y) });
const pieceTools: readonly WhiteboardTool[] = ["offense", "defense", "disc", "cone"];

/** The lowest number not yet taken by a player of [kind] (_nextLabel). */
export function nextLabel(tokens: PlayElement[], kind: PlayElementKind): string {
  if (kind !== "offense" && kind !== "defense") return "";
  const used = new Set(tokens.filter((e) => e.kind === kind).map((e) => Number.parseInt(e.label, 10)));
  let n = 1;
  while (used.has(n)) n++;
  return String(n);
}

/** Halves a stroke (keeping its last point) until it fits [playLimits.drawingPoints]. */
export function thin(points: FieldPoint[]): FieldPoint[] {
  let pts = points;
  while (pts.length > playLimits.drawingPoints) pts = pts.filter((_, i) => i % 2 === 0 || i === pts.length - 1);
  return pts;
}

/** The current board, saved for undo; the oldest falls off past [maxHistory]. */
function push(s: WhiteboardState): Board[] {
  return [...s.history, { strokes: s.strokes, tokens: s.tokens }].slice(-maxHistory);
}

export function whiteboardReducer(s: WhiteboardState, a: WhiteboardAction): WhiteboardState {
  switch (a.type) {
    case "load": {
      // Only a whiteboard is saved back over; a play opened here is a
      // starting sketch, so a save never overwrites its steps.
      const wb = a.doc.kind === "whiteboard";
      return {
        ...s,
        strokes: a.doc.drawings ?? [],
        tokens: a.doc.elements ?? [],
        savedId: wb ? a.id : null,
        name: wb ? (a.doc.name ?? "") : "",
        history: [],
        dirty: false,
      };
    }
    case "tool":
      return { ...s, tool: a.tool };
    case "color":
      // Picking a colour picks the pen too.
      return { ...s, color: a.color, tool: "pen" };
    case "addStroke": {
      // Ignores dots and tiny scribbles; thins long strokes.
      if (a.points.length < 2 || strokesFull(s)) return s;
      let len = 0;
      for (let i = 1; i < a.points.length; i++) {
        const dx = a.points[i]!.x - a.points[i - 1]!.x;
        const dy = a.points[i]!.y - a.points[i - 1]!.y;
        len += dx * dx + dy * dy;
      }
      if (len < 0.00005) return s;
      const stroke: PlayDrawing = { id: a.id, color: s.color, points: thin(a.points.map(clampPoint)) };
      return { ...s, history: push(s), strokes: [...s.strokes, stroke], dirty: true };
    }
    case "place": {
      if (!pieceTools.includes(s.tool) || tokensFull(s)) return s;
      const kind = s.tool as PlayElementKind;
      const token: PlayElement = { id: a.id, kind, position: clampPoint(a.at), label: nextLabel(s.tokens, kind) };
      return { ...s, history: push(s), tokens: [...s.tokens, token], dirty: true };
    }
    case "beginMove":
      // One drag is one undo step.
      return s.tokens.some((e) => e.id === a.id) ? { ...s, history: push(s) } : s;
    case "move":
      return { ...s, tokens: s.tokens.map((e) => (e.id === a.id ? { ...e, position: clampPoint(a.to) } : e)), dirty: true };
    case "erase": {
      if (!s.strokes.some((d) => d.id === a.id) && !s.tokens.some((e) => e.id === a.id)) return s;
      return {
        ...s,
        history: push(s),
        strokes: s.strokes.filter((d) => d.id !== a.id),
        tokens: s.tokens.filter((e) => e.id !== a.id),
        dirty: true,
      };
    }
    case "clear":
      return isEmpty(s) ? s : { ...s, history: push(s), strokes: [], tokens: [], dirty: true };
    case "undo": {
      const prev = s.history[s.history.length - 1];
      if (!prev) return s;
      return { ...s, ...prev, history: s.history.slice(0, -1), dirty: true };
    }
    case "savedPlay":
      return { ...s, dirty: false };
    case "savedWhiteboard":
      return { ...s, savedId: a.id, name: a.name, dirty: false };
  }
}

/**
 * The body for POST/PUT /v1/teams/:id/plays: the pieces where they stand
 * (a play's setup) and the strokes, no steps or arrows. A whiteboard is
 * always "offense", as the app saves it.
 */
export function boardBody(s: Board, save: { kind: "whiteboard"; name: string } | { kind: "play"; name: string; category: PlayDoc["category"] }) {
  return {
    name: save.name.trim(),
    category: save.kind === "play" ? (save.category ?? "offense") : "offense",
    notes: "",
    elements: s.tokens,
    arrows: [],
    steps: [],
    kind: save.kind,
    drawings: s.strokes,
  };
}

// ---- Geometry ----------------------------------------------------------
// Distances are in yards (x across the 40-yard width, y along the 110), so
// a tolerance means the same both ways.

const yards = (p: FieldPoint) => ({ x: p.x * fieldYards.width, y: p.y * fieldYards.length });

function distanceToSegment(p: { x: number; y: number }, a: { x: number; y: number }, b: { x: number; y: number }): number {
  const abx = b.x - a.x;
  const aby = b.y - a.y;
  const len2 = abx * abx + aby * aby;
  if (len2 === 0) return Math.hypot(p.x - a.x, p.y - a.y);
  const t = clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / len2);
  return Math.hypot(p.x - (a.x + abx * t), p.y - (a.y + aby * t));
}

/** Id of the pen stroke within [tolerance] yards of [at], the top one first (hitDrawing). */
export function hitDrawing(drawings: PlayDrawing[], at: FieldPoint, tolerance: number): string | null {
  const o = yards(at);
  for (let k = drawings.length - 1; k >= 0; k--) {
    const d = drawings[k]!;
    const pts = d.points.map(yards);
    if (pts.length === 1 && Math.hypot(pts[0]!.x - o.x, pts[0]!.y - o.y) <= tolerance) return d.id;
    for (let i = 0; i < pts.length - 1; i++) {
      if (distanceToSegment(o, pts[i]!, pts[i + 1]!) <= tolerance) return d.id;
    }
  }
  return null;
}

/**
 * An SVG path through [pts] (already in the field's SVG units), smoothed
 * with quadratic curves through the midpoints as the app paints strokes.
 */
export function smoothPath(pts: Array<{ x: number; y: number }>): string {
  if (pts.length < 2) return "";
  const f = (n: number) => n.toFixed(2);
  let d = `M${f(pts[0]!.x)},${f(pts[0]!.y)}`;
  for (let i = 1; i < pts.length; i++) {
    const p = pts[i]!;
    if (i < pts.length - 1) {
      const n = pts[i + 1]!;
      d += ` Q${f(p.x)},${f(p.y)} ${f((p.x + n.x) / 2)},${f((p.y + n.y) / 2)}`;
    } else d += ` L${f(p.x)},${f(p.y)}`;
  }
  return d;
}

/** "Whiteboard Nov 20", the name a new whiteboard is offered (DateFormat.MMMd). */
export function defaultWhiteboardName(now: Date): string {
  return `Whiteboard ${now.toLocaleDateString("en-US", { month: "short", day: "numeric" })}`;
}
