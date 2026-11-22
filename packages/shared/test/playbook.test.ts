import { describe, expect, it } from "vitest";
import { pathIn, pointAlong, positionsAfter, positionsAt, savePlayRequestSchema } from "../src/playbook.js";

const play = {
  elements: [
    { id: "a", kind: "offense" as const, position: { x: 0.5, y: 0.5 }, label: "1" },
    { id: "d", kind: "disc" as const, position: { x: 0.2, y: 0.2 }, label: "" },
  ],
  steps: [{ id: "s1", note: "", paths: { a: [{ x: 0.5, y: 0.7 }, { x: 0.7, y: 0.7 }] } }],
};

describe("plays", () => {
  it("move pieces along their paths, as the app does", () => {
    expect(positionsAfter(play, 1)).toEqual({ a: { x: 0.7, y: 0.7 }, d: { x: 0.2, y: 0.2 } });
    expect(pathIn(play, 0, "a")).toHaveLength(3);
    expect(pathIn(play, 0, "d")).toEqual([]);
    expect(pointAlong(pathIn(play, 0, "a"), 0.5)).toEqual({ x: 0.5, y: 0.7 });
    expect(positionsAt(play, 0.5).a).toEqual({ x: 0.5, y: 0.7 });
    expect(positionsAt(play, 9).a).toEqual({ x: 0.7, y: 0.7 });
  });

  it("are checked whole: in bounds, ids unique, steps only move pieces on the field", () => {
    const base = { name: "Ho stack", category: "offense", elements: play.elements, steps: play.steps };
    expect(savePlayRequestSchema.safeParse(base).success).toBe(true);
    expect(savePlayRequestSchema.safeParse({ ...base, elements: [{ ...play.elements[0], position: { x: 2, y: 0 } }] }).success).toBe(false);
    expect(savePlayRequestSchema.safeParse({ ...base, elements: [play.elements[0], play.elements[0]] }).success).toBe(false);
    expect(savePlayRequestSchema.safeParse({ ...base, steps: [{ id: "s", paths: { ghost: [] } }] }).success).toBe(false);
    expect(savePlayRequestSchema.safeParse({ ...base, category: "trick" }).success).toBe(false);
  });

  it("carry an optional kind and pen strokes; whiteboards have no steps", () => {
    const base = { name: "Chalk talk", category: "offense", elements: play.elements };
    const stroke = { id: "k1", color: "turf", points: [{ x: 0.1, y: 0.1 }, { x: 0.3, y: 0.4 }] };
    const parsed = savePlayRequestSchema.parse({ ...base, kind: "whiteboard", drawings: [stroke] });
    expect(parsed.kind).toBe("whiteboard");
    expect(parsed.drawings).toEqual([stroke]);
    // Left out, they stay out (the API keeps what the play already has).
    const plain = savePlayRequestSchema.parse(base);
    expect(plain.kind).toBeUndefined();
    expect(plain.drawings).toBeUndefined();
    expect(savePlayRequestSchema.safeParse({ ...base, kind: "whiteboard", steps: play.steps }).success).toBe(false);
    expect(savePlayRequestSchema.safeParse({ ...base, kind: "sketch" }).success).toBe(false);
    expect(savePlayRequestSchema.safeParse({ ...base, drawings: [{ ...stroke, color: "red" }] }).success).toBe(false);
    expect(savePlayRequestSchema.safeParse({ ...base, drawings: [{ ...stroke, points: [stroke.points[0]] }] }).success).toBe(false);
    const long = Array.from({ length: 201 }, (_, i) => ({ x: i / 201, y: 0.5 }));
    expect(savePlayRequestSchema.safeParse({ ...base, drawings: [{ ...stroke, points: long }] }).success).toBe(false);
    expect(savePlayRequestSchema.safeParse({ ...base, drawings: Array.from({ length: 101 }, (_, i) => ({ ...stroke, id: `k${i}` })) }).success).toBe(false);
  });
});
