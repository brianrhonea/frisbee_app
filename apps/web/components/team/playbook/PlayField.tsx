"use client";
import { type FieldPoint, fieldYards, type PlayArrow, type PlayElement } from "@stall10/shared";
import { type PointerEvent, useId, useRef } from "react";

const L = fieldYards.length;
const W = fieldYards.width;

/** A stored point (x across the width, y along the length) on the sideways field. */
const toSvg = (p: FieldPoint) => ({ x: p.y * L, y: p.x * W });
const clamp = (v: number) => Math.min(1, Math.max(0, v));
const toField = (x: number, y: number): FieldPoint => ({ x: clamp(y / W), y: clamp(x / L) });

/** What the pointer touched: a piece, an arrow, or the grass at a point. */
export type FieldHit = { kind: "element" | "arrow"; id: string; at: FieldPoint } | { kind: "field"; at: FieldPoint };

interface FieldHandlers {
  onDown?: (hit: FieldHit) => void;
  onMove?: (at: FieldPoint) => void;
  onUp?: (at: FieldPoint) => void;
}

/**
 * A play on a sideways field (the length running left to right, as the
 * app shows it in landscape): end zones, brick marks, arrows, pieces, and
 * in a step the trails each piece takes. With [handlers] it takes the
 * pointer (mouse, pen or touch) for the editor.
 */
export function PlayField({
  elements,
  arrows,
  positions,
  trails,
  ghost,
  selected,
  label,
  handlers,
}: {
  elements: PlayElement[];
  arrows: PlayArrow[];
  /** Where each piece is shown, if not its setup position. */
  positions?: Record<string, FieldPoint>;
  /** Paths drawn faintly under the pieces (a step's movement). */
  trails?: Array<{ id: string; points: FieldPoint[]; disc: boolean }>;
  /** An arrow being drawn. */
  ghost?: { kind: "cut" | "throw_"; points: FieldPoint[] } | null;
  selected?: string | null;
  label: string;
  handlers?: FieldHandlers;
}) {
  const svg = useRef<SVGSVGElement>(null);
  const marker = useId().replace(/:/g, "");

  function point(e: PointerEvent): FieldPoint {
    const el = svg.current!;
    const m = el.getScreenCTM();
    if (!m) return { x: 0, y: 0 };
    const p = new DOMPoint(e.clientX, e.clientY).matrixTransform(m.inverse());
    return toField(p.x, p.y);
  }
  function hit(at: FieldPoint, target: EventTarget): FieldHit {
    const t = (target as Element).closest?.("[data-id]");
    const id = t?.getAttribute("data-id");
    const kind = t?.getAttribute("data-kind");
    if (id && (kind === "element" || kind === "arrow")) return { kind, id, at };
    // Near a piece counts too, so small dots are easy to grab.
    const s = toSvg(at);
    let best: { id: string; d: number } | null = null;
    for (const e of elements) {
      const q = toSvg(positions?.[e.id] ?? e.position);
      const d = Math.hypot(q.x - s.x, q.y - s.y);
      if (d < 3.2 && (!best || d < best.d)) best = { id: e.id, d };
    }
    return best ? { kind: "element", id: best.id, at } : { kind: "field", at };
  }

  const line = (pts: FieldPoint[]) => pts.map((p) => `${toSvg(p).x.toFixed(2)},${toSvg(p).y.toFixed(2)}`).join(" ");
  return (
    <svg
      ref={svg}
      className={`field${handlers ? " field-edit" : ""}`}
      viewBox={`0 0 ${L} ${W}`}
      role="img"
      aria-label={label}
      onPointerDown={
        handlers &&
        ((e) => {
          if (e.button !== 0) return;
          (e.currentTarget as SVGSVGElement).setPointerCapture(e.pointerId);
          const at = point(e);
          handlers.onDown?.(hit(at, e.target));
        })
      }
      onPointerMove={handlers && ((e) => e.buttons && handlers.onMove?.(point(e)))}
      onPointerUp={handlers && ((e) => handlers.onUp?.(point(e)))}
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
