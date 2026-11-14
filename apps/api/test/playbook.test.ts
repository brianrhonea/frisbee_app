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
});
