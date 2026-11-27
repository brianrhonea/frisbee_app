// The roster's O-line / D-line (PUT /v1/teams/:id/roster-lines) and its
// pending invites (GET / DELETE /v1/teams/:id/invites), against FakeStore.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { listDocQueries } from "../src/queries.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

function setup() {
  const store = new FakeStore();
  // The collection group query, over every document FakeStore holds.
  const queries = {
    ...listDocQueries(store),
    async group(collectionId: string, limit: number, where: Record<string, string | boolean>) {
      return [...store.docs.entries()]
        .filter(([path, data]) => {
          const parts = path.split("/");
          return parts[parts.length - 2] === collectionId && Object.entries(where).every(([k, v]) => data[k] === v);
        })
        .slice(0, limit)
        .map(([path, data]) => ({ path, data: structuredClone(data) }));
    },
  };
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), store, queries });
  const call = (method: "GET" | "PUT" | "POST" | "DELETE", url: string, uid: string, body?: object) =>
    app.inject({ method, url, headers: { authorization: `Bearer token:${uid}` }, ...(body !== undefined && { payload: body }) });
  return { store, call };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.store.put("teams/t1", {
    name: "Northside Flyers",
    kind: "team",
    ownerId: "olive",
    memberIds: ["olive", "pat", "cap"],
    members: { olive: "owner", pat: "player", cap: "player" },
    roles: { r1: { name: "Captains", position: 0, perms: ["manageTeam"] } },
    memberRoles: { cap: ["r1"] },
    memberPerms: { cap: ["manageTeam"] },
  });
  s.store.put("teams/t1/roster/a", { name: "Pat", number: 7, position: "handler", userId: "pat" });
  s.store.put("teams/t1/roster/b", { name: "Sam", number: null, position: "cutter", userId: null });
});

describe("roster lines", () => {
  const url = "/v1/teams/t1/roster-lines";

  it("admins who change the roster set and clear lines; the roster shows them", async () => {
    expect((await s.call("PUT", url, "cap", { lines: { a: "o", b: "both" } })).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/roster/a")).toMatchObject({ line: "o" });
    expect(s.store.doc("teams/t1/roster/b")).toMatchObject({ line: "both" });
    const roster = (await s.call("GET", "/v1/teams/t1/roster", "pat")).json();
    expect(roster.players.map((p: { id: string; line?: string }) => [p.id, p.line])).toEqual([
      ["a", "o"],
      ["b", "both"],
    ]);
    expect((await s.call("PUT", url, "olive", { lines: { b: null } })).statusCode).toBe(204);
    expect(s.store.doc("teams/t1/roster/b")).not.toHaveProperty("line");
    expect(s.store.doc("teams/t1/roster/a")).toMatchObject({ line: "o" });
  });

  it("players can't, and every spot must still be on the roster", async () => {
    expect((await s.call("PUT", url, "pat", { lines: { a: "d" } })).statusCode).toBe(403);
    expect((await s.call("PUT", url, "olive", { lines: { a: "d", ghost: "o" } })).statusCode).toBe(404);
    expect(s.store.doc("teams/t1/roster/a")).not.toHaveProperty("line");
  });

  it("takes only O, D or both, for at least one spot", async () => {
    expect((await s.call("PUT", url, "olive", { lines: { a: "x" } })).statusCode).toBe(400);
    expect((await s.call("PUT", url, "olive", { lines: {} })).statusCode).toBe(400);
    expect((await s.call("PUT", url, "olive", { lines: { a: "o" }, extra: 1 })).statusCode).toBe(400);
  });

  it("groups have no lines", async () => {
    s.store.put("teams/g1", { name: "Pickup", kind: "community", memberIds: ["olive"], members: { olive: "owner" } });
    s.store.put("teams/g1/roster/x", { name: "X", position: "hybrid" });
    expect((await s.call("PUT", "/v1/teams/g1/roster-lines", "olive", { lines: { x: "o" } })).statusCode).toBe(412);
  });

  it("editing or linking a spot keeps its line", async () => {
    await s.call("PUT", url, "olive", { lines: { a: "d", b: "o" } });
    const save = await s.call("PUT", "/v1/teams/t1/roster-players/a", "olive", { name: "Pat P", number: 8, position: "hybrid", userId: "pat" });
    expect(save.statusCode).toBe(204);
    expect(s.store.doc("teams/t1/roster/a")).toEqual({ name: "Pat P", number: 8, position: "hybrid", userId: "pat", line: "d" });
    const link = await s.call("PUT", "/v1/teams/t1/roster-players/b/link", "olive", { userId: "cap" });
    expect(link.statusCode).toBe(204);
    expect(s.store.doc("teams/t1/roster/b")).toMatchObject({ userId: "cap", line: "o" });
  });
});

describe("pending invites", () => {
  const url = "/v1/teams/t1/invites";
  beforeEach(() => {
    s.store.put("users/new/teamInvites/t1", {
      teamId: "t1",
      teamName: "Northside Flyers",
      invitedBy: "olive",
      invitedByName: "Olive",
      createdAt: new Date("2026-11-01T10:00:00Z"),
    });
    s.store.put("users/newer/teamInvites/t1", { teamId: "t1", invitedByName: "Olive", createdAt: new Date("2026-11-02T10:00:00Z") });
    s.store.put("users/other/teamInvites/t2", { teamId: "t2", createdAt: new Date() });
    // Joined since: not pending any more.
    s.store.put("users/pat/teamInvites/t1", { teamId: "t1", createdAt: new Date() });
    s.store.put("profiles/new", { name: "Nina New", username: "nina", email: "secret@x" });
  });

  it("lists who's still invited, newest first, public cards only, for those who invite", async () => {
    s.store.put("teams/t1", { ...s.store.doc("teams/t1"), memberPerms: { cap: ["manageMembers"] } });
    const res = await s.call("GET", url, "cap");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      invites: [
        { uid: "newer", name: "Someone", invitedByName: "Olive", invitedAt: "2026-11-02T10:00:00.000Z" },
        { uid: "new", name: "Nina New", username: "nina", invitedByName: "Olive", invitedAt: "2026-11-01T10:00:00.000Z" },
      ],
    });
  });

  it("passes on only a trusted profile photo (3a-F)", async () => {
    s.store.put("teams/t1", { ...s.store.doc("teams/t1"), memberPerms: { cap: ["manageMembers"] } });
    s.store.put("profiles/new", { name: "Nina New", username: "nina", photoUrl: "https://tracker.example/p.gif" });
    const bad = (await s.call("GET", url, "cap")).json().invites.find((i: { uid: string }) => i.uid === "new");
    expect(bad).not.toHaveProperty("photoUrl");
    s.store.put("profiles/new", { name: "Nina New", username: "nina", photoUrl: "https://lh3.googleusercontent.com/a/n" });
    const good = (await s.call("GET", url, "cap")).json().invites.find((i: { uid: string }) => i.uid === "new");
    expect(good.photoUrl).toBe("https://lh3.googleusercontent.com/a/n");
  });

  it("players can't see or withdraw them", async () => {
    expect((await s.call("GET", url, "pat")).statusCode).toBe(403);
    expect((await s.call("DELETE", `${url}/new`, "pat")).statusCode).toBe(403);
    expect(s.store.doc("users/new/teamInvites/t1")).toBeDefined();
  });

  it("the owner withdraws one", async () => {
    expect((await s.call("DELETE", `${url}/new`, "olive")).statusCode).toBe(200);
    expect(s.store.doc("users/new/teamInvites/t1")).toBeUndefined();
    expect((await s.call("GET", url, "olive")).json().invites.map((i: { uid: string }) => i.uid)).toEqual(["newer"]);
  });
});
