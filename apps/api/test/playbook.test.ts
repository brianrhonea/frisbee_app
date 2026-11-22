// Plays, following the plays rule.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
let store: FakeStore;
let call: (method: "POST" | "PUT" | "DELETE", url: string, body?: object, uid?: string) => Promise<{ status: number; json: () => any }>;
const play = {
  name: "Ho stack",
  category: "offense",
  notes: "Swing it",
  elements: [{ id: "a1", kind: "offense", position: { x: 0.5, y: 0.5 }, label: "1" }],
  arrows: [{ id: "c1", kind: "cut", points: [{ x: 0.5, y: 0.5 }, { x: 0.6, y: 0.3 }] }],
  steps: [{ id: "s1", note: "Go", paths: { a1: [{ x: 0.6, y: 0.3 }] } }],
};

beforeEach(() => {
  store = new FakeStore(() => now);
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
  call = async (method, url, body, uid = "coach") => {
    const res = await app.inject({ method, url, ...(body && { payload: body }), headers: { authorization: `Bearer token:${uid}` } });
    return { status: res.statusCode, json: () => res.json() };
  };
  store.put("teams/t1", { ownerId: "owner", memberIds: ["owner", "coach", "player"], members: { owner: "owner", coach: "coach", player: "player" } });
});

describe("plays", () => {
  it("are saved by the team's admins, with who saved them", async () => {
    expect((await call("POST", "/v1/teams/t1/plays", play, "player")).status).toBe(403);
    expect((await call("POST", "/v1/teams/t1/plays", play, "stranger")).status).toBe(403);
    const res = await call("POST", "/v1/teams/t1/plays", play);
    expect(res.status).toBe(201);
    const id = res.json().id;
    expect(store.doc(`teams/t1/plays/${id}`)).toMatchObject({ name: "Ho stack", updatedBy: "coach", updatedAt: new Date(now) });
    expect((await call("PUT", `/v1/teams/t1/plays/${id}`, { ...play, name: "Vert" })).status).toBe(204);
    expect(store.doc(`teams/t1/plays/${id}`)?.name).toBe("Vert");
    expect((await call("PUT", "/v1/teams/t1/plays/ghost", play)).status).toBe(404);
    expect((await call("DELETE", `/v1/teams/t1/plays/${id}`, undefined, "player")).status).toBe(403);
    expect((await call("DELETE", `/v1/teams/t1/plays/${id}`)).status).toBe(204);
    expect(store.doc(`teams/t1/plays/${id}`)).toBeUndefined();
  });

  it("refuse extra fields and bad shapes", async () => {
    expect((await call("POST", "/v1/teams/t1/plays", { ...play, updatedBy: "owner" })).status).toBe(400);
    expect((await call("POST", "/v1/teams/t1/plays", { ...play, elements: [{ ...play.elements[0], position: { x: -1, y: 0 } }] })).status).toBe(400);
    expect((await call("POST", "/v1/teams/t1/plays", { ...play, name: "" })).status).toBe(400);
  });

  it("save whiteboards and pen strokes, and keep them when a save leaves them out", async () => {
    const stroke = { id: "k1", color: "amber", points: [{ x: 0.1, y: 0.1 }, { x: 0.4, y: 0.2 }] };
    const board = { name: "Chalk talk", category: "offense", elements: play.elements, kind: "whiteboard", drawings: [stroke] };
    expect((await call("POST", "/v1/teams/t1/plays", board, "player")).status).toBe(403);
    const res = await call("POST", "/v1/teams/t1/plays", board);
    expect(res.status).toBe(201);
    const id = res.json().id;
    expect(store.doc(`teams/t1/plays/${id}`)).toMatchObject({ kind: "whiteboard", drawings: [stroke], steps: [] });
    // An older client's save (no kind, no drawings) doesn't turn it into a play.
    expect((await call("PUT", `/v1/teams/t1/plays/${id}`, { name: "Renamed", category: "offense", elements: play.elements })).status).toBe(204);
    expect(store.doc(`teams/t1/plays/${id}`)).toMatchObject({ name: "Renamed", kind: "whiteboard", drawings: [stroke] });
    expect((await call("PUT", `/v1/teams/t1/plays/${id}`, { name: "Renamed", category: "offense", elements: play.elements, steps: play.steps })).status).toBe(400);
    // Saved as a play, with no strokes: both fields go.
    expect((await call("PUT", `/v1/teams/t1/plays/${id}`, { ...play, kind: "play", drawings: [] })).status).toBe(204);
    const saved = store.doc(`teams/t1/plays/${id}`);
    expect(saved?.kind).toBeUndefined();
    expect(saved?.drawings).toBeUndefined();
    // A plain play stores neither field.
    const plain = (await call("POST", "/v1/teams/t1/plays", play)).json().id;
    expect(Object.keys(store.doc(`teams/t1/plays/${plain}`) ?? {})).not.toContain("kind");
    expect((await call("POST", "/v1/teams/t1/plays", { ...board, drawings: [{ ...stroke, color: "red" }] })).status).toBe(400);
  });
});
