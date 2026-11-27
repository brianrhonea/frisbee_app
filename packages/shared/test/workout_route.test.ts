// decodeRoutePath and workoutSchema's route (Sprint 4 A2), against Google's documented polyline example.
import { describe, expect, it } from "vitest";
import { decodeRoutePath, workoutSchema } from "../src/index.js";

const google = "_p~iF~ps|U_ulLnnqC_mqNvxq`@";

describe("decodeRoutePath", () => {
  it("decodes Google's reference polyline", () => {
    expect(decodeRoutePath(google)).toEqual([
      [38.5, -120.2],
      [40.7, -120.95],
      [43.252, -126.453],
    ]);
  });
  it("is null for a truncated, out-of-alphabet or oversize path", () => {
    expect(decodeRoutePath("_p~iF~ps|U_")).toBeNull();
    expect(decodeRoutePath("hello world")).toBeNull();
    expect(decodeRoutePath(google, 2)).toBeNull();
  });
  it("is an empty list for an empty string", () => {
    expect(decodeRoutePath("")).toEqual([]);
  });
});

describe("workoutSchema with a route", () => {
  const base = { activity: "run", durationMinutes: 30, route: { path: google } };
  it("accepts a recorded run and fills the splits", () => {
    const r = workoutSchema.safeParse({ ...base, durationSeconds: 1800, distanceKm: 5 });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.route).toEqual({ path: google, splitsMi: [], splitsKm: [] });
  });
  it("still takes a hand-typed workout, and refuses a route that is not a route", () => {
    expect(workoutSchema.safeParse({ activity: "gym", durationMinutes: 30 }).success).toBe(true);
    expect(workoutSchema.safeParse({ ...base, route: { path: "abc" } }).success).toBe(false);
    expect(workoutSchema.safeParse({ ...base, distanceKm: 500 }).success).toBe(false);
  });
});
