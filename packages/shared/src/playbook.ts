// A team's plays (teams/{id}/plays, Play in the app): pieces on a field,
// arrows for cuts and throws, animation steps and freehand pen strokes
// (drawings). A saved whiteboard is a play with kind "whiteboard" and no
// steps. Points are 0–1 in both
// axes: x across the 40-yard width, y along the 110-yard length.
import { z } from "zod";

export const playCategories = ["offense", "defense", "pull", "endzone"] as const;
export type PlayCategory = (typeof playCategories)[number];
export const playCategoryLabels: Record<PlayCategory, string> = { offense: "Offense", defense: "Defense", pull: "Pull", endzone: "Endzone" };

export const playElementKinds = ["offense", "defense", "disc", "cone"] as const;
export type PlayElementKind = (typeof playElementKinds)[number];
export const playArrowKinds = ["cut", "throw_"] as const;
export type PlayArrowKind = (typeof playArrowKinds)[number];
/** "whiteboard": a saved sketch, listed under the playbook's Whiteboard switch. Missing means "play". */
export const playKinds = ["play", "whiteboard"] as const;
export type PlayKind = (typeof playKinds)[number];
/** Pen colours by name; each platform draws its own shade (FieldColors in the app). */
export const drawingColors = ["ink", "turf", "amber", "white"] as const;
export type DrawingColor = (typeof drawingColors)[number];

/** The rules' limits, and the app's path cap (_maxPathPoints). */
export const playLimits = {
  name: 100,
  notes: 5000,
  elements: 100,
  arrows: 100,
  steps: 30,
  arrowPoints: 200,
  pathPoints: 48,
  label: 20,
  stepNote: 200,
  drawings: 100,
  drawingPoints: 200,
} as const;

/** Field size in yards (FieldGeometry). */
export const fieldYards = { width: 40, length: 110, endzone: 20, brick: 20 } as const;

const itemId = z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/, "Invalid id.");
const unit = z.number().finite().min(0).max(1);
export const fieldPointSchema = z.strictObject({ x: unit, y: unit });
export type FieldPoint = z.output<typeof fieldPointSchema>;

export const playElementSchema = z.strictObject({
  id: itemId,
  kind: z.enum(playElementKinds),
  position: fieldPointSchema,
  label: z.string().max(playLimits.label).default(""),
});
export type PlayElement = z.output<typeof playElementSchema>;

export const playArrowSchema = z.strictObject({
  id: itemId,
  kind: z.enum(playArrowKinds),
  points: z.array(fieldPointSchema).min(2).max(playLimits.arrowPoints),
});
export type PlayArrow = z.output<typeof playArrowSchema>;

/** A freehand pen stroke (PlayDrawing). */
export const playDrawingSchema = z.strictObject({
  id: itemId,
  color: z.enum(drawingColors),
  points: z.array(fieldPointSchema).min(2).max(playLimits.drawingPoints),
});
export type PlayDrawing = z.output<typeof playDrawingSchema>;

export const playStepSchema = z.strictObject({
  id: itemId,
  note: z.string().max(playLimits.stepNote).default(""),
  /** Element id → waypoints after where the previous step left it. */
  paths: z
    .record(itemId, z.array(fieldPointSchema).max(playLimits.pathPoints))
    .refine((p) => Object.keys(p).length <= playLimits.elements, "Too many moving pieces."),
});
export type PlayStep = z.output<typeof playStepSchema>;

/** `POST /v1/teams/:teamId/plays` and `PUT .../plays/:playId`: the whole play. */
export const savePlayRequestSchema = z
  .strictObject({
    name: z.string().trim().min(1, "Name the play.").max(playLimits.name),
    category: z.enum(playCategories),
    notes: z.string().max(playLimits.notes).default(""),
    elements: z.array(playElementSchema).max(playLimits.elements),
    arrows: z.array(playArrowSchema).max(playLimits.arrows).default([]),
    steps: z.array(playStepSchema).max(playLimits.steps).default([]),
    // Optional, not defaulted: a save that leaves them out keeps what the
    // play already has (an older client mustn't turn a whiteboard into a
    // play or drop its strokes).
    kind: z.enum(playKinds).optional(),
    drawings: z.array(playDrawingSchema).max(playLimits.drawings).optional(),
  })
  .superRefine((p, ctx) => {
    if (p.kind === "whiteboard" && p.steps.length > 0) ctx.addIssue({ code: "custom", path: ["steps"], message: "A whiteboard has no steps." });
    const ids = new Set(p.elements.map((e) => e.id));
    if (ids.size !== p.elements.length) ctx.addIssue({ code: "custom", path: ["elements"], message: "Each piece needs its own id." });
    for (const [i, s] of p.steps.entries()) {
      for (const id of Object.keys(s.paths)) {
        if (!ids.has(id)) ctx.addIssue({ code: "custom", path: ["steps", i, "paths"], message: "A step moves a piece that isn't on the field." });
      }
    }
  });
export type SavePlayInput = z.output<typeof savePlayRequestSchema>;

/** A stored play. */
export interface PlayDoc {
  name?: string;
  category?: PlayCategory;
  notes?: string;
  elements?: PlayElement[];
  arrows?: PlayArrow[];
  steps?: PlayStep[];
  /** Missing means "play". */
  kind?: PlayKind;
  drawings?: PlayDrawing[];
  updatedAt?: string;
  updatedBy?: string;
}

/** Element id → where it is once [step] steps have played (0 = setup); Play.positionsAfter. */
export function positionsAfter(play: Pick<PlayDoc, "elements" | "steps">, step: number): Record<string, FieldPoint> {
  const pos: Record<string, FieldPoint> = {};
  for (const e of play.elements ?? []) pos[e.id] = e.position;
  for (const s of (play.steps ?? []).slice(0, step)) {
    for (const [id, path] of Object.entries(s.paths ?? {})) {
      if (pos[id] && path.length) pos[id] = path[path.length - 1]!;
    }
  }
  return pos;
}

/** Where [id] goes during step [index]: its start, then its waypoints; empty if it doesn't move (Play.pathIn). */
export function pathIn(play: Pick<PlayDoc, "elements" | "steps">, index: number, id: string): FieldPoint[] {
  const way = play.steps?.[index]?.paths?.[id];
  const start = positionsAfter(play, index)[id];
  return way && start ? [start, ...way] : [];
}

/** The point [f] (0–1) of the way along [path], by distance (Play.pointAlong). */
export function pointAlong(path: FieldPoint[], f: number): FieldPoint {
  if (path.length === 1 || f <= 0) return path[0]!;
  if (f >= 1) return path[path.length - 1]!;
  // As the app measures it (sqrt of the squares, not Math.hypot), so the
  // points come out bit for bit the same.
  const dist = (a: FieldPoint, b: FieldPoint) => Math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
  let total = 0;
  for (let i = 1; i < path.length; i++) total += dist(path[i - 1]!, path[i]!);
  if (total === 0) return path[path.length - 1]!;
  let remaining = total * f;
  for (let i = 1; i < path.length; i++) {
    const d = dist(path[i - 1]!, path[i]!);
    if (remaining <= d) {
      const r = d === 0 ? 0 : remaining / d;
      const a = path[i - 1]!;
      const b = path[i]!;
      return { x: a.x + (b.x - a.x) * r, y: a.y + (b.y - a.y) * r };
    }
    remaining -= d;
  }
  return path[path.length - 1]!;
}

const easeInOut = (x: number) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);

/** Element id → position at time [t] (0 = setup, k..k+1 plays step k), easing each step (Play.positionsAt). */
export function positionsAt(play: Pick<PlayDoc, "elements" | "steps">, t: number): Record<string, FieldPoint> {
  const steps = play.steps ?? [];
  if (steps.length === 0 || t <= 0) return positionsAfter(play, 0);
  if (t >= steps.length) return positionsAfter(play, steps.length);
  const k = Math.floor(t);
  const f = easeInOut(t - k);
  const pos = positionsAfter(play, k);
  for (const id of Object.keys(steps[k]!.paths ?? {})) {
    const path = pathIn(play, k, id);
    if (path.length > 1) pos[id] = pointAlong(path, f);
  }
  return pos;
}
