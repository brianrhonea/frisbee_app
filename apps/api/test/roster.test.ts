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
  s.store.put("profiles/pat", { name: "Pat Public", username: "pat", photoUrl: "https://lh3.googleusercontent.com/a/p" });
  s.store.put("profiles/quinn", { name: "Quinn Quiet", private: true });
});

describe("roster photos (3a-F)", () => {
  it("drops a profile photo that isn't ours or Google's, on players and members", async () => {
    s.store.put("profiles/pat", { name: "Pat Public", username: "pat", photoUrl: "https://tracker.example/p.gif" });
    const body = (await s.get("/v1/teams/t1/roster")).json();
    expect(body.players[0].person).toEqual({ uid: "pat", name: "Pat Public", username: "pat" });
    expect(JSON.stringify(body)).not.toContain("tracker.example");
  });
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
          person: { uid: "pat", name: "Pat Public", username: "pat", photoUrl: "https://lh3.googleusercontent.com/a/p" },
        },
        { id: "b", name: "Sam Sub", position: "cutter" },
      ],
      members: [
        { uid: "olive", name: "Olive Owner", tier: "owner", roles: [] },
        { uid: "pat", name: "Pat Public", username: "pat", photoUrl: "https://lh3.googleusercontent.com/a/p", tier: "player", roles: ["Captains", "Handlers"] },
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

  it("keeps a youth team's roster to its members and its school or club's member managers", async () => {
    s.store.put("teams/y1", {
      name: "Juniors",
      level: "youth",
      memberIds: ["olive", "pat"],
      members: { olive: "owner", pat: "player" },
      orgId: "school",
      orgLinked: true,
    });
    s.store.put("teams/y1/roster/a", { name: "Kid Player", number: 4, position: "cutter" });
    s.store.put("teams/school", {
      name: "Austin High",
      kind: "organization",
      memberIds: ["admin", "helper", "parent"],
      members: { admin: "owner", helper: "player", parent: "player" },
      memberPerms: { helper: ["manageMembers"] },
      linkedTeams: { y1: { name: "Juniors" } },
    });
    for (const uid of ["visitor", "parent"]) {
      const res = await s.get("/v1/teams/y1/roster", uid);
      expect(res.statusCode, uid).toBe(403);
      expect(res.json().error.message).toBe("Rosters of youth teams are private: only members see them.");
      expect(res.body).not.toContain("Kid Player");
    }
    for (const uid of ["pat", "admin", "helper"]) {
      const res = await s.get("/v1/teams/y1/roster", uid);
      expect(res.statusCode, uid).toBe(200);
      expect(res.json().players[0].name).toBe("Kid Player");
    }
    // A community that hasn't accepted the team (or doesn't list it) doesn't open it.
    s.store.put("teams/y2", { name: "Juniors 2", level: "youth", memberIds: ["olive"], members: { olive: "owner" }, orgId: "school", orgLinked: false });
    s.store.put("teams/y3", { name: "Juniors 3", level: "youth", memberIds: ["olive"], members: { olive: "owner" }, orgId: "school", orgLinked: true });
    for (const id of ["y2", "y3"]) expect((await s.get(`/v1/teams/${id}/roster`, "admin")).statusCode, id).toBe(403);
    // Adult teams are unchanged: anyone signed in.
    expect((await s.get("/v1/teams/t1/roster", "visitor")).statusCode).toBe(200);
  });

  it("keeps a team's roster to its members while its public page is off", async () => {
    s.store.put("teams/t1", { ...s.store.doc("teams/t1")!, publicPage: false });
    const res = await s.get("/v1/teams/t1/roster", "visitor");
    expect(res.statusCode).toBe(403);
    expect(res.json().error.message).toBe("This team's page is private: only members see its roster.");
    expect(res.body).not.toContain("Pat Public");
    expect((await s.get("/v1/teams/t1/roster", "quinn")).statusCode).toBe(200);
  });

  it("keeps a team in a youth league division to its members, whatever its level says", async () => {
    s.store.put("tournaments/lg", { name: "Junior League", divisions: [{ id: "d1", level: "youth", division: "mixed" }] });
    s.store.put("teams/lt", { name: "Team 1", level: "league", leagueId: "lg", memberIds: ["pat"], members: { pat: "owner" } });
    s.store.put("tournaments/lg/entries/lt", { divisionId: "d1", teamName: "Team 1" });
    s.store.put("teams/lt/roster/a", { name: "Kid Player", number: 4 });
    const res = await s.get("/v1/teams/lt/roster", "visitor");
    expect(res.statusCode).toBe(403);
    expect(res.body).not.toContain("Kid Player");
    expect((await s.get("/v1/teams/lt/roster", "pat")).statusCode).toBe(200);
    // An adult division of the same kind of league stays open to anyone signed in.
    s.store.put("tournaments/al", { name: "Adult League", divisions: [{ id: "d1", level: "club", division: "mixed" }] });
    s.store.put("teams/at", { name: "Team 2", level: "league", leagueId: "al", memberIds: ["pat"], members: { pat: "owner" } });
    s.store.put("tournaments/al/entries/at", { divisionId: "d1", teamName: "Team 2" });
    expect((await s.get("/v1/teams/at/roster", "visitor")).statusCode).toBe(200);
  });

  it("reads the profile cards in one getAll", async () => {
    expect((await s.get("/v1/teams/t1/roster")).statusCode).toBe(200);
    expect(s.store.getAllCalls).toBe(1);
  });

  it("caps each member's roster reads (60 a minute)", async () => {
    for (let i = 0; i < 60; i++) expect((await s.get("/v1/teams/t1/roster")).statusCode).toBe(200);
    expect((await s.get("/v1/teams/t1/roster")).statusCode).toBe(429);
    // Someone else's reads are their own.
    expect((await s.get("/v1/teams/t1/roster", "pat")).statusCode).toBe(200);
  });

  it("answers 404 for a missing team and 400 for a bad id", async () => {
    expect((await s.get("/v1/teams/nope/roster")).statusCode).toBe(404);
    expect((await s.get("/v1/teams/__x__/roster")).statusCode).toBe(400);
  });
});
