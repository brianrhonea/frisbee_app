// The app's play animation (apps/mobile/lib/domain/models/play.dart)
// against playbook.ts, on the vectors in fixtures/playbook (written by
// apps/mobile/test/shared_fixtures/playbook_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { type FieldPoint, pathIn, type PlayDoc, pointAlong, positionsAfter, positionsAt } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

type Positions = Record<string, FieldPoint>;

interface AnimationCase {
  play: PlayDoc & { id: string; name: string };
  positionsAfter: Positions[];
  pathIn: Array<Record<string, FieldPoint[]>>;
  positionsAt: Array<{ t: number; positions: Positions }>;
}

describe("play animation matches the app (fixtures/playbook/animation.json)", () => {
  it.each(fixture<AnimationCase>("playbook/animation.json").cases.map((c) => ({ ...c, name: c.play.name })))("$name", (c) => {
    const steps = c.play.steps ?? [];
    expect(c.positionsAfter.map((_, s) => positionsAfter(c.play, s))).toEqual(c.positionsAfter);
    expect(steps.map((st, i) => Object.fromEntries(Object.keys(st.paths).map((id) => [id, pathIn(c.play, i, id)])))).toEqual(c.pathIn);
    expect(c.positionsAt.map(({ t }) => ({ t, positions: positionsAt(c.play, t) }))).toEqual(c.positionsAt);
  });
});

describe("points along a path match the app (fixtures/playbook/point_along.json)", () => {
  it.each(fixture<{ path: FieldPoint[]; points: Array<{ f: number; point: FieldPoint }> }>("playbook/point_along.json").cases.map((c, i) => ({ ...c, i })))(
    "path $i",
    (c) => {
      expect(c.points.map(({ f }) => ({ f, point: pointAlong(c.path, f) }))).toEqual(c.points);
    },
  );
});
