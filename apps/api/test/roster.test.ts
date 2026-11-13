// A team's roster for anyone signed in, against FakeStore: only public
// fields go out, and a private group keeps its members to itself.
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier } from "./fakes.js";

function setup() {
  const store = new FakeStore();
  const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), store });
  const get = (url: string, uid: string | null = "visitor") =>
    app.inject({ method: "GET", url, headers: uid ? { authorization: `Bearer token:${uid}` } : {} });
  return { store, get };
}

let s: ReturnType<typeof setup>;
beforeEach(() => {
  s = setup();
  s.store.put("teams/t1", {
    name: "Northside Flyers",
    kind: "team",
    ownerId: "olive",
    memberIds: ["olive", "pat", "quinn"],
    members: { olive: "owner", pat: "player", quinn: "player" },
    memberNames: { olive: "Olive Owner", pat: "Pat", quinn: "Quinn Q" },
    roles: { r1: { name: "Handlers", position: 1, perms: ["keepStats"] }, r0: { name: "Captains", position: 0, perms: [] } },
    memberRoles: { pat: ["r1", "r0"] },
    memberPerms: { pat: ["keepStats"] },
    statKeepers: ["pat"],
  });
  s.store.put("teams/t1/roster/a", { name: "Pat Public", number: 7, position: "handler", userId: "pat" });
  s.store.put("teams/t1/roster/b", { name: "Sam Sub", position: "cutter" });
  s.store.put("teams/t1/rosterStatus/a", { paid: true });
  s.store.put("profiles/pat", { name: "Pat Public", username: "pat", photoUrl: "https://img/p.jpg" });
  s.store.put("profiles/quinn", { name: "Quinn Quiet", private: true });
});

describe("roster", () => {
  it("shows players and members to anyone signed in, with public cards only", async () => {
    const res = await s.get("/v1/teams/t1/roster");
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      kind: "team",
      players: [
        {
          id: "a",
          name: "Pat Public",
          number: 7,
          position: "handler",
          person: { uid: "pat", name: "Pat Public", username: "pat", photoUrl: "https://img/p.jpg" },
        },
        { id: "b", name: "Sam Sub", position: "cutter" },
      ],
      members: [
        { uid: "olive", name: "Olive Owner", tier: "owner", roles: [] },
        { uid: "pat", name: "Pat Public", username: "pat", photoUrl: "https://img/p.jpg", tier: "player", roles: ["Captains", "Handlers"] },
        { uid: "quinn", name: "Quinn Quiet", private: true, tier: "player", roles: [] },
      ],
      teams: [],
    });
  });

  it("needs a signed-in caller", async () => {
    expect((await s.get("/v1/teams/t1/roster", null)).statusCode).toBe(401);
  });

  it("keeps a private group's members to its members", async () => {
    s.store.put("teams/g1", {
      name: "Thursday Pickup",
      kind: "community",
      requiresApproval: true,
      memberIds: ["olive"],
      members: { olive: "owner" },
    });
    s.store.put("teams/g1/roster/x", { name: "Not a team roster", position: "hybrid" });
    expect((await s.get("/v1/teams/g1/roster")).statusCode).toBe(403);
    const res = await s.get("/v1/teams/g1/roster", "olive");
    expect(res.json()).toMatchObject({ kind: "community", players: [], members: [{ uid: "olive", tier: "owner" }] });
  });

  it("keeps a private organization's members to its members too", async () => {
    s.store.put("teams/o1", { name: "City League", kind: "organization", requiresApproval: true, memberIds: ["olive"], members: { olive: "owner" } });
    expect((await s.get("/v1/teams/o1/roster")).statusCode).toBe(403);
    s.store.put("teams/o2", {
      name: "Open League",
      kind: "organization",
      requiresApproval: false,
      memberIds: ["olive"],
      members: { olive: "owner" },
      linkedTeams: { z: { name: "Zephyr", division: "open", roles: ["r1"] }, a: { name: "Aces", roles: [] } },
    });
    expect((await s.get("/v1/teams/o2/roster")).json()).toMatchObject({
      kind: "organization",
      members: [{ uid: "olive" }],
      teams: [{ id: "a", name: "Aces" }, { id: "z", name: "Zephyr", division: "open" }],
    });
  });

  it("answers 404 for a missing team and 400 for a bad id", async () => {
    expect((await s.get("/v1/teams/nope/roster")).statusCode).toBe(404);
    expect((await s.get("/v1/teams/__x__/roster")).statusCode).toBe(400);
  });
});
