// News on a hosted tournament or league: a public team post on the host
// with a tournamentKey (validPost's last conjunct in firestore.rules: no
// key, or a string of at most 300 characters matching
// 'tournament_' + teamId + '_.+'). One test per part of that conjunct.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeMediaStorage, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

const now = Date.UTC(2026, 10, 14, 12);
let store: FakeStore;
let call: (method: "POST" | "PATCH", url: string, body: object, uid?: string) => Promise<{ status: number; json: () => any }>;

beforeEach(() => {
  store = new FakeStore(() => now);
  const users = new FakeUsers();
  users.records.set("owner", { name: "Olive Owner", email: "o@x.test" });
  const app = buildApp({ verifier: new FakeVerifier(), users, teams: new FakeTeamRepository(), store, media: new FakeMediaStorage(), now: () => now });
  call = async (method, url, body, uid = "owner") => {
    const res = await app.inject({ method, url, payload: body, headers: { authorization: `Bearer token:${uid}` } });
    return { status: res.statusCode, json: () => res.json() };
  };
  store.put("teams/host", {
    name: "Host Club",
    kind: "organization",
    ownerId: "owner",
    memberIds: ["owner", "events", "player"],
    members: { owner: "owner", events: "player", player: "player" },
    memberPerms: { events: ["manageEvents"] },
  });
});

const news = (extra: object = {}) => ({ title: "Semis at 2", body: "Field 3.", public: true, ...extra });

describe("tournament news (validPost tournamentKey)", () => {
  it("a post without a key has none (key == null)", async () => {
    const res = await call("POST", "/v1/teams/host/posts", news());
    expect(res.status).toBe(201);
    expect(store.doc(`teams/host/posts/${res.json().id}`)).not.toHaveProperty("tournamentKey");
  });

  it("stores a key for one of this team's tournaments", async () => {
    const res = await call("POST", "/v1/teams/host/posts", news({ tournamentKey: "tournament_host_t1" }));
    expect(res.status).toBe(201);
    expect(store.doc(`teams/host/posts/${res.json().id}`)).toMatchObject({ tournamentKey: "tournament_host_t1", public: true, title: "Semis at 2" });
  });

  it("refuses a key that isn't a string (validString)", async () => {
    expect((await call("POST", "/v1/teams/host/posts", news({ tournamentKey: 42 }))).status).toBe(400);
  });

  it("refuses a key over 300 characters (validString(…, 300))", async () => {
    expect((await call("POST", "/v1/teams/host/posts", news({ tournamentKey: `tournament_host_${"x".repeat(290)}` }))).status).toBe(400);
  });

  it("refuses another team's tournament (matches 'tournament_' + teamId + '_')", async () => {
    expect((await call("POST", "/v1/teams/host/posts", news({ tournamentKey: "tournament_other_t1" }))).status).toBe(400);
    expect((await call("POST", "/v1/teams/host/posts", news({ tournamentKey: "team_host_t1" }))).status).toBe(400);
  });

  it("refuses a key with no tournament after the prefix (the '.+')", async () => {
    expect((await call("POST", "/v1/teams/host/posts", news({ tournamentKey: "tournament_host_" }))).status).toBe(400);
  });

  it("refuses a tournament part that isn't a plain id", async () => {
    expect((await call("POST", "/v1/teams/host/posts", news({ tournamentKey: "tournament_host_a/b" }))).status).toBe(400);
  });

  it("is posted only by those who manage the host (can(team(), 'manageTeam'))", async () => {
    expect((await call("POST", "/v1/teams/host/posts", news({ tournamentKey: "tournament_host_t1" }), "events")).status).toBe(403);
    expect((await call("POST", "/v1/teams/host/posts", news({ tournamentKey: "tournament_host_t1" }), "player")).status).toBe(403);
  });

  it("an edit keeps the key when it isn't sent, and changes it when it is", async () => {
    const res = await call("POST", "/v1/teams/host/posts", news({ tournamentKey: "tournament_host_t1" }));
    const id = res.json().id as string;
    expect((await call("PATCH", `/v1/teams/host/posts/${id}`, news({ body: "Field 4." }))).status).toBe(200);
    expect(store.doc(`teams/host/posts/${id}`)).toMatchObject({ tournamentKey: "tournament_host_t1", body: "Field 4." });
    expect((await call("PATCH", `/v1/teams/host/posts/${id}`, news({ tournamentKey: "tournament_host_t2" }))).status).toBe(200);
    expect(store.doc(`teams/host/posts/${id}`)?.tournamentKey).toBe("tournament_host_t2");
    expect((await call("PATCH", `/v1/teams/host/posts/${id}`, news({ tournamentKey: "tournament_other_t2" }))).status).toBe(400);
  });
});
