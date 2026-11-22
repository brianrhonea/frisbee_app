"use client";
import { type DrawingColor, type FieldPoint, fieldYards, type PlayArrow, type PlayDrawing, type PlayElement } from "@stall10/shared";
import { type PointerEvent, type RefObject, useEffect, useId, useRef, useState } from "react";
import { hitDrawing, smoothPath } from "./whiteboard_state";

const L = fieldYards.length;
const W = fieldYards.width;

/** A stored point (x across the width, y along the length) on the sideways field. */
const toSvg = (p: FieldPoint) => ({ x: p.y * L, y: p.x * W });
const clamp = (v: number) => Math.min(1, Math.max(0, v));
const toField = (x: number, y: number): FieldPoint => ({ x: clamp(y / W), y: clamp(x / L) });

/** What the pointer touched: a piece, an arrow, a pen stroke, or the grass at a point. */
export type FieldHit = { kind: "element" | "arrow" | "drawing"; id: string; at: FieldPoint } | { kind: "field"; at: FieldPoint };

interface FieldHandlers {
  onDown?: (hit: FieldHit) => void;
  /** While the pointer is down; [drawing] is the pen stroke under it now, if any. */
  onMove?: (at: FieldPoint, drawing: string | null) => void;
  onUp?: (at: FieldPoint) => void;
}

/** A pen stroke's width in field units: 1% of the short side, and at least 2.5px (FieldPainter). */
function useStrokeWidth(svg: RefObject<SVGSVGElement | null>, on: boolean) {
  const [width, setWidth] = useState(W * 0.01);
  useEffect(() => {
    const el = svg.current;
    if (!on || !el || typeof ResizeObserver === "undefined") return;
    const measure = () => {
      const px = el.getBoundingClientRect().width;
      if (px > 0) setWidth(Math.max(W * 0.01, (2.5 * L) / px));
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [svg, on]);
  return width;
}

/**
 * A play on a sideways field (the length running left to right, as the
 * app shows it in landscape): end zones, brick marks, pen strokes, arrows,
 * pieces, and in a step the trails each piece takes. With [handlers] it
 * takes one pointer at a time (mouse, pen or touch) for the editors.
 */
export function PlayField({
  elements,
  arrows,
  drawings,
  draft,
  positions,
  trails,
  ghost,
  selected,
  label,
  handlers,
  className,
}: {
  elements: PlayElement[];
  arrows: PlayArrow[];
  /** Freehand pen strokes, on the grass under arrows and pieces. */
  drawings?: PlayDrawing[];
  /** A pen stroke being drawn. */
  draft?: { color: DrawingColor; points: FieldPoint[] } | null;
  /** Where each piece is shown, if not its setup position. */
  positions?: Record<string, FieldPoint>;
  /** Paths drawn faintly under the pieces (a step's movement). */
  trails?: Array<{ id: string; points: FieldPoint[]; disc: boolean }>;
  /** An arrow being drawn. */
  ghost?: { kind: "cut" | "throw_"; points: FieldPoint[] } | null;
  selected?: string | null;
  label: string;
  handlers?: FieldHandlers;
  className?: string;
}) {
  const svg = useRef<SVGSVGElement>(null);
  const marker = useId().replace(/:/g, "");
  const pointer = useRef<number | null>(null);
  const strokes = drawings ?? [];
  const penWidth = useStrokeWidth(svg, strokes.length > 0 || !!draft || !!handlers);
  // Handlers taken away mid-gesture (playback started) leave no pointer held.
  const editable = !!handlers;
  useEffect(() => {
    if (!editable) pointer.current = null;
  }, [editable]);

  function point(e: PointerEvent): FieldPoint {
    const el = svg.current!;
    const m = el.getScreenCTM();
    if (!m) return { x: 0, y: 0 };
    const p = new DOMPoint(e.clientX, e.clientY).matrixTransform(m.inverse());
    return toField(p.x, p.y);
  }
  /** Field units (yards) per screen pixel. */
  function unitsPerPx(): number {
    const px = svg.current?.getBoundingClientRect().width ?? 0;
    return px > 0 ? L / px : 0.5;
  }
  function hit(at: FieldPoint, target: EventTarget | null): FieldHit {
    const t = (target as Element | null)?.closest?.("[data-id]");
    const id = t?.getAttribute("data-id");
    const kind = t?.getAttribute("data-kind");
    // A piece or arrow clicked directly wins.
    if (id && (kind === "element" || kind === "arrow")) return { kind, id, at };
    // Near a piece counts too, so small dots are easy to grab.
    const s = toSvg(at);
    let best: { id: string; d: number } | null = null;
    for (const e of elements) {
      const q = toSvg(positions?.[e.id] ?? e.position);
      const d = Math.hypot(q.x - s.x, q.y - s.y);
      if (d < 3.2 && (!best || d < best.d)) best = { id: e.id, d };
    }
    if (best) return { kind: "element", id: best.id, at };
    // Then a pen stroke within reach (14px, as the app's FieldGeometry).
    const stroke = hitDrawing(strokes, at, Math.max(1.6, 14 * unitsPerPx()));
    return stroke ? { kind: "drawing", id: stroke, at } : { kind: "field", at };
  }
  const end = (e: PointerEvent) => {
    if (pointer.current !== e.pointerId) return;
    pointer.current = null;
    handlers?.onUp?.(point(e));
  };

  const line = (pts: FieldPoint[]) => pts.map((p) => `${toSvg(p).x.toFixed(2)},${toSvg(p).y.toFixed(2)}`).join(" ");
  return (
    <svg
      ref={svg}
      className={`field${handlers ? " field-edit" : ""}${className ? ` ${className}` : ""}`}
      viewBox={`0 0 ${L} ${W}`}
      role="img"
      aria-label={label}
      onPointerDown={
        handlers &&
        ((e) => {
          // One pointer at a time: a second finger doesn't start another stroke.
          if (e.button !== 0 || pointer.current !== null) return;
          pointer.current = e.pointerId;
          (e.currentTarget as SVGSVGElement).setPointerCapture(e.pointerId);
          handlers.onDown?.(hit(point(e), e.target));
        })
      }
      onPointerMove={
        handlers &&
        ((e) => {
          if (pointer.current !== e.pointerId || !e.buttons) return;
          const at = point(e);
          // Captured moves all target the field itself, so the stroke is found by distance.
          handlers.onMove?.(at, hitDrawing(strokes, at, Math.max(1.6, 14 * unitsPerPx())));
        })
      }
      onPointerUp={handlers && end}
      onPointerCancel={handlers && end}
      onLostPointerCapture={handlers && end}
    >
      <defs>
        <marker id={`a${marker}`} viewBox="0 0 6 6" refX="5" refY="3" markerWidth="4" markerHeight="4" orient="auto-start-reverse">
          <path d="M0,0 L6,3 L0,6 z" className="field-arrow-head" />
        </marker>
      </defs>
      <rect x="0" y="0" width={L} height={W} className="field-grass" />
      <line x1={fieldYards.endzone} y1="0" x2={fieldYards.endzone} y2={W} className="field-line" />
      <line x1={L - fieldYards.endzone} y1="0" x2={L - fieldYards.endzone} y2={W} className="field-line" />
      {[fieldYards.endzone + fieldYards.brick, L - fieldYards.endzone - fieldYards.brick].map((x) => (
        <g key={x} className="field-brick">
          <line x1={x - 0.6} y1={W / 2} x2={x + 0.6} y2={W / 2} />
          <line x1={x} y1={W / 2 - 0.6} x2={x} y2={W / 2 + 0.6} />
        </g>
      ))}
      {strokes.map((d) => (
        <path key={d.id} data-id={d.id} data-kind="drawing" d={smoothPath(d.points.map(toSvg))} className={`field-pen ${d.color}`} strokeWidth={penWidth} />
      ))}
      {draft && draft.points.length > 1 && <path d={smoothPath(draft.points.map(toSvg))} className={`field-pen ${draft.color}`} strokeWidth={penWidth} />}
      {(trails ?? []).map((t) => (
        <polyline key={`t-${t.id}`} points={line(t.points)} className={t.disc ? "field-trail disc" : "field-trail"} markerEnd={`url(#a${marker})`} />
      ))}
      {arrows.map((a) => (
        <g key={a.id} data-id={a.id} data-kind="arrow" className={selected === a.id ? "field-selected" : undefined}>
          {handlers && <polyline points={line(a.points)} className="field-hit-line" />}
          <polyline points={line(a.points)} className={a.kind === "throw_" ? "field-throw" : "field-cut"} markerEnd={`url(#a${marker})`} />
        </g>
      ))}
      {ghost && ghost.points.length > 1 && (
        <polyline points={line(ghost.kind === "throw_" ? [ghost.points[0]!, ghost.points[ghost.points.length - 1]!] : ghost.points)} className={ghost.kind === "throw_" ? "field-throw" : "field-cut"} markerEnd={`url(#a${marker})`} />
      )}
      {elements.map((e) => {
        const p = toSvg(positions?.[e.id] ?? e.position);
        return (
          <g key={e.id} data-id={e.id} data-kind="element" className={`field-el ${e.kind}${selected === e.id ? " field-selected" : ""}`}>
            {e.kind === "cone" ? (
              <path d={`M${p.x},${p.y - 1.6} L${p.x + 1.4},${p.y + 1.2} L${p.x - 1.4},${p.y + 1.2} z`} />
            ) : (
              <circle cx={p.x} cy={p.y} r={e.kind === "disc" ? 1.1 : 2} />
            )}
            {e.label && (e.kind === "offense" || e.kind === "defense") && (
              <text x={p.x} y={p.y + 0.8} textAnchor="middle">
                {e.label.slice(0, 2)}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}
