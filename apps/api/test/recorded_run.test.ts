// A recorded GPS run posted through POST /v1/posts (Sprint 4 A2): the route, exact time and distance the app
// used to write straight to Firestore, checked as firestore.rules' validWorkout / validRoute check them.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 12, 12);

/** Google's encoded polyline, 5 decimals, as the app's encodePolyline writes it. */
function encode(points: [number, number][]): string {
  let out = "";
  let lastLat = 0;
  let lastLng = 0;
  const write = (v: number) => {
    let x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) {
      out += String.fromCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    out += String.fromCharCode(x + 63);
  };
  for (const [la, ln] of points) {
    const lat = Math.round(la * 1e5);
    const lng = Math.round(ln * 1e5);
    write(lat - lastLat);
    write(lng - lastLng);
    lastLat = lat;
    lastLng = lng;
  }
  return out;
}

const line = (n: number): [number, number][] => Array.from({ length: n }, (_, i) => [41 + i * 1e-4, -87 - i * 1e-4]);

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const media = new FakeMediaStorage();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media, now: () => now });
  const call = (body: object, uid: string | null = "me") =>
    app.inject({ method: "POST", url: "/v1/posts", payload: body, headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
  return { store, users, media, call };
}

function uploaded(s: ReturnType<typeof setup>, id: string, postId: string, uid = "me") {
  const path = `users/${uid}/posts/${postId}/${id}/${id}.jpg`;
  s.store.put(`uploads/${id}`, { uid, purpose: "post", itemId: postId, status: "ready", path, thumbPath: path.replace(".jpg", "_thumb.jpg"), contentType: "image/jpeg", actualSize: 1234 });
  s.media.files.set(path, { data: Buffer.from("x") });
  s.media.files.set(path.replace(".jpg", "_thumb.jpg"), { data: Buffer.from("x") });
  return path;
}

const run = (route: object = { path: encode(line(50)), splitsMi: [480, 470], splitsKm: [300, 295, 298], elevationGainM: 42.4 }) => ({
  activity: "run",
  durationMinutes: 21,
  durationSeconds: 1234,
  distanceKm: 3.456,
  route,
});

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.users.records.set("me", { name: "Mia Member", email: "mia@x.test", photoUrl: "https://img/m.jpg" });
});

describe("recorded runs on POST /v1/posts", () => {
  it("stores a valid run as the app stores one, with a replayable id and photos", async () => {
    const path = uploaded(s, "u1", "run1");
    const res = await s.call({ id: "run1", body: "Morning loop", workout: run(), uploadIds: ["u1"] });
    expect(res.statusCode).toBe(201);
    expect(res.json().id).toBe("run1");
    expect(s.store.doc("posts/run1")).toMatchObject({
      kind: "workout",
      authorId: "me",
      workout: {
        activity: "run",
        durationMinutes: 21,
        durationSeconds: 1234,
        distanceKm: 3.46,
        route: { splitsMi: [480, 470], splitsKm: [300, 295, 298], elevationGainM: 42 },
      },
    });
    expect((s.store.doc("posts/run1")!.workout as { route: { path: string } }).route.path).toBe(encode(line(50)));
    expect(JSON.stringify(s.store.doc("posts/run1")!.images)).toContain(path);
  });

  it("accepts a route at the limits, and a run with no splits or climb", async () => {
    expect((await s.call({ workout: run({ path: encode(line(4000)), splitsMi: [], splitsKm: [] }) })).statusCode).toBe(201);
    const many = Array.from({ length: 1000 }, () => 400);
    expect((await s.call({ workout: run({ path: encode(line(2)), splitsMi: many, splitsKm: many, elevationGainM: 20000 }) })).statusCode).toBe(201);
  });

  it("refuses a route with too many points or too long a path", async () => {
    expect((await s.call({ workout: run({ path: encode(line(4001)), splitsMi: [], splitsKm: [] }) })).statusCode).toBe(400);
    expect((await s.call({ workout: run({ path: "?".repeat(80001), splitsMi: [], splitsKm: [] }) })).statusCode).toBe(400);
    expect((await s.call({ workout: run({ path: encode(line(1)), splitsMi: [], splitsKm: [] }) })).statusCode).toBe(400);
  });

  it("refuses coordinates off the globe and a malformed path", async () => {
    expect((await s.call({ workout: run({ path: encode([[41, -87], [91, -87]]), splitsMi: [], splitsKm: [] }) })).statusCode).toBe(400);
    expect((await s.call({ workout: run({ path: encode([[41, -87], [41, 181]]), splitsMi: [], splitsKm: [] }) })).statusCode).toBe(400);
    expect((await s.call({ workout: run({ path: "not a polyline!", splitsMi: [], splitsKm: [] }) })).statusCode).toBe(400);
    expect((await s.call({ workout: run({ path: "_p~iF~ps|U_", splitsMi: [], splitsKm: [] }) })).statusCode).toBe(400);
  });

  it("refuses out-of-range numbers, unknown route fields and an impossible pace", async () => {
    const path = encode(line(10));
    const bad = [
      { ...run(), durationSeconds: 0 },
      { ...run(), durationSeconds: 86401 },
      { ...run(), distanceKm: 1001 },
      { ...run(), distanceKm: 0 },
      { ...run(), durationSeconds: 60, durationMinutes: 1, distanceKm: 20 },
      run({ path, splitsMi: [0], splitsKm: [] }),
      run({ path, splitsMi: [1.5], splitsKm: [] }),
      run({ path, splitsMi: new Array(1001).fill(400), splitsKm: [] }),
      run({ path, splitsMi: [], splitsKm: [], elevationGainM: -1 }),
      run({ path, splitsMi: [], splitsKm: [], elevationGainM: 20001 }),
      run({ path, splitsMi: [], splitsKm: [], extra: 1 }),
    ];
    for (const [i, workout] of bad.entries()) expect((await s.call({ workout }, `bad${i}`)).statusCode, JSON.stringify(workout).slice(0, 120)).toBe(400);
  });

  it("only takes photos that are this caller's finished uploads for this post", async () => {
    uploaded(s, "other", "run2", "pat");
    expect((await s.call({ id: "run2", workout: run(), uploadIds: ["other"] })).statusCode).toBe(400);
    uploaded(s, "wrongpost", "elsewhere");
    expect((await s.call({ id: "run3", workout: run(), uploadIds: ["wrongpost"] })).statusCode).toBe(400);
    expect((await s.call({ id: "run4", workout: run(), uploadIds: ["nope"] })).statusCode).toBeGreaterThanOrEqual(400);
    expect(s.store.doc("posts/run2")).toBeUndefined();
  });

  it("answers 401 without a session, and writes nothing", async () => {
    expect((await s.call({ workout: run() }, null)).statusCode).toBe(401);
    expect([...s.store.docs.keys()].some((k) => k.startsWith("posts/"))).toBe(false);
  });

  it("takes a body over the old 64 KB limit when a route needs it", async () => {
    const worst = "\\".repeat(80000);
    const res = await s.call({ workout: run({ path: worst, splitsMi: [], splitsKm: [] }) });
    expect(res.statusCode).not.toBe(413); // refused for its content (not a real polyline), not for its size
  });
});
