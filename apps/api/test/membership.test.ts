// Team membership and management through the API, against FakeStore. Each
// describe follows one rule function in firebase/firestore.rules, with a
// test per condition it checks.
import { searchKeywords } from "@stall10/shared";
import { beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { FakeCipher, FakeStore, FakeTeamRepository, FakeUsers, FakeVerifier, seedBirthDate } from "./fakes.js";

const now = Date.UTC(2026, 10, 11, 12);
const T = "teams/t1";

/** A team: an owner, a legacy coach, players (one a stat keeper, one a manageMembers role). */
function seedTeam(over: Record<string, unknown> = {}) {
  return {
    name: "The Haze",
    division: "open",
    level: "club",
    city: "Austin",
    ownerId: "owner",
    members: { owner: "owner", coach: "coach", p1: "player", mgr: "player", old: "stats" },
    memberIds: ["owner", "coach", "p1", "mgr", "old"],
    memberNames: { owner: "Olive", coach: "Cody", p1: "Pat", mgr: "Max", old: "Stan" },
    statKeepers: ["p1"],
    roles: { r1: { name: "Manager", color: 0, position: 0, perms: ["manageMembers"] } },
    memberRoles: { mgr: ["r1"] },
    memberPerms: { mgr: ["manageMembers"] },
    createdAt: new Date(now - 1000),
    ...over,
  };
}

const group = (over: Record<string, unknown> = {}) =>
  seedTeam({
    name: "Austin Pickup",
    division: "mixed",
    level: "pickup",
    kind: "community",
    description: "Sundays",
    requiresApproval: false,
    location: { address: "Zilker", lat: 30.2, lng: -97.7 },
    ...over,
  });

function setup() {
  const store = new FakeStore(() => now);
  const users = new FakeUsers();
  const teams = new FakeTeamRepository();
  const cipher = new FakeCipher();
  const app = buildApp({ verifier: new FakeVerifier(), users, teams, store, personal: cipher, now: () => now });
  const call = (method: "POST" | "PUT" | "PATCH" | "DELETE", url: string, uid: string, body?: object) =>
    app.inject({
      method,
      url,
      headers: { authorization: `Bearer token:${uid}:Name ${uid}` },
      ...(body !== undefined && { payload: body }),
    });
  return { store, users, teams, cipher, app, call };
}

let s: ReturnType<typeof setup>;
beforeEach(async () => {
  s = setup();
  // "new" (who joins in most tests) is an adult: the club team below takes them.
  await seedBirthDate(s.store, s.cipher, "new", "1998-04-02");
});

const team = () => s.store.doc(T)!;
const err = (res: { json(): unknown }) => (res.json() as { error: { code: string; message: string } }).error;

describe("join with a code or link (join)", () => {
  const code = (over: Record<string, unknown> = {}) =>
    s.store.put("inviteCodes/ABC234", { teamId: "t1", createdBy: "owner", createdAt: new Date(now - 10_000), ttl: 45, expiresAt: new Date(now + 35_000), ...over });

  beforeEach(() => s.store.put(T, seedTeam()));

  it("adds the caller as a player named from their Auth record, with the join proof", async () => {
    code();
    s.users.records.set("new", { name: "Nia Real" });
    const res = await s.call("POST", "/v1/teams/join", "new", { code: " abc-234 " });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ teamId: "t1" });
    expect(team().members).toMatchObject({ new: "player" });
    expect(team().memberIds).toEqual(["owner", "coach", "p1", "mgr", "old", "new"]);
    expect(team().memberNames).toMatchObject({ new: "Nia Real" });
    expect(s.store.doc("teams/t1/joins/new")).toEqual({ code: "ABC234" });
  });

  it("refuses an unknown code", async () => {
    const res = await s.call("POST", "/v1/teams/join", "new", { code: "ZZZZZZ" });
    expect(res.statusCode).toBe(404);
    expect(err(res).message).toBe("No team found for that invite code.");
  });

  it("checks liveness on the server's clock (createdAt + ttl), not expiresAt", async () => {
    code({ createdAt: new Date(now - 46_000), expiresAt: new Date(now + 60_000) });
    const res = await s.call("POST", "/v1/teams/join", "new", { code: "ABC234" });
    expect(res.statusCode).toBe(412);
    expect(err(res).message).toBe("That invite has expired. Ask for a new code or link.");
    expect(team().memberIds).not.toContain("new");
  });

  it("refuses a code from before rotation (no createdAt or ttl)", async () => {
    s.store.put("inviteCodes/ABC234", { teamId: "t1" });
    expect((await s.call("POST", "/v1/teams/join", "new", { code: "ABC234" })).statusCode).toBe(412);
  });

  it("leaves a member's role alone (no-op)", async () => {
    code();
    const res = await s.call("POST", "/v1/teams/join", "coach", { code: "ABC234" });
    expect(res.statusCode).toBe(200);
    expect(team().members).toMatchObject({ coach: "coach" });
    expect(s.store.doc("teams/t1/joins/coach")).toBeUndefined();
  });

  it("caps the name at 80 characters", async () => {
    code();
    s.users.records.set("new", { name: "x".repeat(100) });
    await s.call("POST", "/v1/teams/join", "new", { code: "ABC234" });
    expect((team().memberNames as Record<string, string>).new).toHaveLength(80);
  });

  it("needs a signed-in caller", async () => {
    const res = await s.app.inject({ method: "POST", url: "/v1/teams/join", payload: { code: "ABC234" } });
    expect(res.statusCode).toBe(401);
  });
});

describe("ids in the path", () => {
  it("refuses one that isn't a single document id, even sent as %2F", async () => {
    s.store.put("teams/t1/chats/x", { name: "room" });
    const res = await s.call("POST", "/v1/teams/t1%2Fchats%2Fx/members", "new", {});
    expect(res.statusCode).toBe(400);
    expect(s.store.doc("teams/t1/chats/x")).toEqual({ name: "room" });
  });
});

describe("join an open group (joinOpenGroup)", () => {
  it("adds anyone to an open group", async () => {
    s.store.put(T, group());
    expect((await s.call("POST", "/v1/teams/t1/members", "new", {})).statusCode).toBe(200);
    expect(team().members).toMatchObject({ new: "player" });
  });

  it("refuses a group that needs approval", async () => {
    s.store.put(T, group({ requiresApproval: true }));
    const res = await s.call("POST", "/v1/teams/t1/members", "new", {});
    expect(res.statusCode).toBe(412);
    expect(team().memberIds).not.toContain("new");
  });

  it("refuses a team", async () => {
    s.store.put(T, seedTeam());
    expect((await s.call("POST", "/v1/teams/t1/members", "new", {})).statusCode).toBe(403);
  });

  it("404s a missing team", async () => {
    expect((await s.call("POST", "/v1/teams/nope/members", "new", {})).statusCode).toBe(404);
  });
});

describe("join requests", () => {
  beforeEach(() => s.store.put(T, group({ requiresApproval: true })));
  const R = "teams/t1/joinRequests/new";

  it("records a request with the caller's name and the server's time", async () => {
    s.users.records.set("new", { name: "Nia" });
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "new", {})).statusCode).toBe(200);
    expect(s.store.doc(R)).toEqual({ name: "Nia", createdAt: new Date(now) });
  });

  it("turns away a muted caller", async () => {
    s.store.put("limits/new", { mutedUntil: new Date(now + 60_000) });
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "new", {})).statusCode).toBe(429);
    expect(s.store.doc(R)).toBeUndefined();
  });

  it("only for a group that needs approval, or a team that allows requests", async () => {
    s.store.put(T, group({ requiresApproval: false }));
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "new", {})).statusCode).toBe(412);
    s.store.put(T, seedTeam());
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "new", {})).statusCode).toBe(412);
    s.store.put(T, seedTeam({ allowJoinRequests: true, leagueId: "lg1" }));
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "new", {})).statusCode).toBe(412);
    s.store.put(T, seedTeam({ allowJoinRequests: true }));
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "new", {})).statusCode).toBe(200);
  });

  it("not from a member", async () => {
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "p1", {})).statusCode).toBe(409);
  });

  it("keeps the first request when asked again", async () => {
    s.store.put(R, { name: "Nia", createdAt: new Date(0) });
    await s.call("POST", "/v1/teams/t1/join-requests", "new", {});
    expect(s.store.doc(R)!.createdAt).toEqual(new Date(0));
  });

  it("an admin with manageMembers approves: member named as asked, request cleared", async () => {
    s.store.put(R, { name: "Nia", createdAt: new Date(0) });
    expect((await s.call("POST", "/v1/teams/t1/join-requests/new/approve", "mgr", {})).statusCode).toBe(200);
    expect(team().members).toMatchObject({ new: "player" });
    expect(team().memberNames).toMatchObject({ new: "Nia" });
    expect(s.store.doc(R)).toBeUndefined();
  });

  it("names a nameless request 'Member'", async () => {
    s.store.put(R, { name: "", createdAt: new Date(0) });
    await s.call("POST", "/v1/teams/t1/join-requests/new/approve", "owner", {});
    expect(team().memberNames).toMatchObject({ new: "Member" });
  });

  it("players can't approve", async () => {
    s.store.put(R, { name: "Nia" });
    expect((await s.call("POST", "/v1/teams/t1/join-requests/new/approve", "p1", {})).statusCode).toBe(403);
    expect(team().memberIds).not.toContain("new");
  });

  it("approving needs a request", async () => {
    expect((await s.call("POST", "/v1/teams/t1/join-requests/new/approve", "owner", {})).statusCode).toBe(404);
  });

  it("a team that doesn't allow requests can't approve one", async () => {
    s.store.put(T, seedTeam());
    s.store.put(R, { name: "Nia" });
    expect((await s.call("POST", "/v1/teams/t1/join-requests/new/approve", "owner", {})).statusCode).toBe(412);
    expect(team().memberIds).not.toContain("new");
  });

  it("the asker withdraws; a manager declines; nobody else", async () => {
    s.store.put(R, { name: "Nia" });
    expect((await s.call("DELETE", "/v1/teams/t1/join-requests/new", "p1")).statusCode).toBe(403);
    expect(s.store.doc(R)).toBeDefined();
    expect((await s.call("DELETE", "/v1/teams/t1/join-requests/new", "new")).statusCode).toBe(200);
    expect(s.store.doc(R)).toBeUndefined();
    s.store.put(R, { name: "Nia" });
    expect((await s.call("DELETE", "/v1/teams/t1/join-requests/new", "mgr")).statusCode).toBe(200);
    expect(s.store.doc(R)).toBeUndefined();
  });
});

describe("invites (teamInvites, acceptInvite)", () => {
  const I = "users/new/teamInvites/t1";
  beforeEach(() => s.store.put(T, seedTeam()));

  it("a manageMembers admin invites someone, named from the Auth record", async () => {
    s.users.records.set("mgr", { name: "Max Real" });
    expect((await s.call("POST", "/v1/teams/t1/invites", "mgr", { uid: "new" })).statusCode).toBe(200);
    expect(s.store.doc(I)).toEqual({
      teamId: "t1",
      teamName: "The Haze",
      kind: "team",
      invitedBy: "mgr",
      invitedByName: "Max Real",
      createdAt: new Date(now),
    });
  });

  it("a community's member managers invite to the teams it accepted", async () => {
    s.store.put(T, { ...seedTeam(), orgId: "org", orgLinked: true });
    s.store.put("teams/org", {
      name: "UT Dallas",
      kind: "organization",
      memberIds: ["boss", "helper", "fan"],
      members: { boss: "owner", helper: "player", fan: "player" },
      memberPerms: { helper: ["manageMembers"] },
      linkedTeams: { t1: { name: "The Haze", division: "mixed", roles: [] } },
    });
    expect((await s.call("POST", "/v1/teams/t1/invites", "boss", { uid: "new" })).statusCode).toBe(200);
    expect(s.store.doc(I)).toMatchObject({ teamName: "The Haze", kind: "team", invitedBy: "boss" });
    expect((await s.call("POST", "/v1/teams/t1/invites", "helper", { uid: "new2" })).statusCode).toBe(200);
    // A plain community member can't.
    expect((await s.call("POST", "/v1/teams/t1/invites", "fan", { uid: "new3" })).statusCode).toBe(403);
  });

  it("community admins can't invite to a team the community hasn't accepted or listed", async () => {
    s.store.put("teams/org", { name: "UT Dallas", kind: "organization", memberIds: ["boss"], members: { boss: "owner" }, linkedTeams: {} });
    s.store.put(T, { ...seedTeam(), orgId: "org", orgLinked: false });
    expect((await s.call("POST", "/v1/teams/t1/invites", "boss", { uid: "new" })).statusCode).toBe(403);
    s.store.put(T, { ...seedTeam(), orgId: "org", orgLinked: true });
    expect((await s.call("POST", "/v1/teams/t1/invites", "boss", { uid: "new" })).statusCode).toBe(403);
  });

  it("players can't invite", async () => {
    expect((await s.call("POST", "/v1/teams/t1/invites", "p1", { uid: "new" })).statusCode).toBe(403);
  });

  it("can't invite a member", async () => {
    expect((await s.call("POST", "/v1/teams/t1/invites", "owner", { uid: "p1" })).statusCode).toBe(409);
  });

  it("the invitee accepts: joins as a player; invite and join request cleared", async () => {
    s.store.put(I, { teamName: "The Haze" });
    s.store.put("teams/t1/joinRequests/new", { name: "x" });
    expect((await s.call("POST", "/v1/me/team-invites/t1/accept", "new", {})).statusCode).toBe(200);
    expect(team().members).toMatchObject({ new: "player" });
    expect(s.store.doc(I)).toBeUndefined();
    expect(s.store.doc("teams/t1/joinRequests/new")).toBeUndefined();
  });

  it("accepting needs an invite", async () => {
    expect((await s.call("POST", "/v1/me/team-invites/t1/accept", "new", {})).statusCode).toBe(404);
    expect(team().memberIds).not.toContain("new");
  });

  it("only one's own invite: someone else can't use it", async () => {
    s.store.put(I, { teamName: "The Haze" });
    expect((await s.call("POST", "/v1/me/team-invites/t1/accept", "other", {})).statusCode).toBe(404);
  });

  it("declining deletes it", async () => {
    s.store.put(I, { teamName: "The Haze" });
    expect((await s.call("DELETE", "/v1/me/team-invites/t1", "new")).statusCode).toBe(200);
    expect(s.store.doc(I)).toBeUndefined();
  });
});

describe("leave and remove (removeMember)", () => {
  beforeEach(() => s.store.put(T, seedTeam({ orgMembers: ["p1"] })));
  const remove = (who: string, by: string) => s.call("DELETE", `/v1/teams/t1/members/${who}`, by);

  it("a member leaves; stats, roles, perms and community membership go too", async () => {
    expect((await remove("mgr", "mgr")).statusCode).toBe(200);
    const t = team();
    expect(t.members).not.toHaveProperty("mgr");
    expect(t.memberIds).not.toContain("mgr");
    expect(t.memberNames).not.toHaveProperty("mgr");
    expect(t.memberRoles).toEqual({});
    expect(t.memberPerms).toEqual({});
    await remove("p1", "p1");
    expect(team().statKeepers).toEqual([]);
    expect(team().orgMembers).toEqual([]);
  });

  it("the owner can't leave or be removed", async () => {
    expect((await remove("owner", "owner")).statusCode).toBe(412);
    expect((await remove("owner", "coach")).statusCode).toBe(412);
    expect(team().memberIds).toContain("owner");
  });

  it("the owner removes anyone else", async () => {
    expect((await remove("coach", "owner")).statusCode).toBe(200);
    expect((await remove("mgr", "owner")).statusCode).toBe(200);
  });

  it("coaches and manageMembers members remove players with no permissions", async () => {
    expect((await remove("p1", "mgr")).statusCode).toBe(200);
    expect((await remove("old", "coach")).statusCode).toBe(200);
  });

  it("but not players with permissions, nor coaches", async () => {
    expect((await remove("mgr", "coach")).statusCode).toBe(403);
    expect((await remove("coach", "mgr")).statusCode).toBe(403);
  });

  it("a player can't remove anyone else", async () => {
    expect((await remove("old", "p1")).statusCode).toBe(403);
  });

  it("404s someone not on the team", async () => {
    expect((await remove("ghost", "owner")).statusCode).toBe(404);
  });
});

describe("change role (changeRole)", () => {
  beforeEach(() => s.store.put(T, seedTeam()));
  const set = (who: string, role: string, by = "owner") =>
    s.call("PUT", `/v1/teams/t1/members/${who}/role`, by, { role });

  it("the owner moves a legacy coach down to player", async () => {
    expect((await set("coach", "player")).statusCode).toBe(200);
    expect(team().members).toMatchObject({ coach: "player" });
  });

  it("only the owner", async () => {
    expect((await set("p1", "player", "coach")).statusCode).toBe(403);
  });

  it("nobody new becomes a coach or captain", async () => {
    expect((await set("p1", "coach")).statusCode).toBe(412);
    expect((await set("p1", "captain")).statusCode).toBe(412);
    expect((await set("coach", "captain")).statusCode).toBe(412);
  });

  it("nobody becomes a second owner (transfer instead)", async () => {
    expect((await set("p1", "owner")).statusCode).toBe(412);
  });

  it("the owner's own role doesn't change", async () => {
    expect((await set("owner", "player")).statusCode).toBe(412);
  });

  it("no new 'stats' tier", async () => {
    expect((await set("p1", "stats")).statusCode).toBe(400);
  });

  it("a legacy stats member may become a player, once no legacy coach is left", async () => {
    // As in the rule: while coaches or captains remain, the only change
    // allowed is moving one of them down (migrateTiersToRoles does that).
    expect((await set("old", "player")).statusCode).toBe(412);
    await set("coach", "player");
    expect((await set("old", "player")).statusCode).toBe(200);
  });

  it("404s a non-member; no-op when unchanged", async () => {
    expect((await set("ghost", "player")).statusCode).toBe(404);
    expect((await set("p1", "player")).statusCode).toBe(200);
  });
});

describe("stat keepers (setStatKeepers)", () => {
  beforeEach(() => s.store.put(T, seedTeam()));
  const set = (who: string, on: boolean, by = "owner") =>
    s.call("PUT", `/v1/teams/t1/members/${who}/stat-keeper`, by, { on });

  it("the owner turns stats access on and off", async () => {
    expect((await set("mgr", true)).statusCode).toBe(200);
    expect(team().statKeepers).toEqual(["p1", "mgr"]);
    expect((await set("p1", false)).statusCode).toBe(200);
    expect(team().statKeepers).toEqual(["mgr"]);
  });

  it("only the owner", async () => {
    expect((await set("mgr", true, "coach")).statusCode).toBe(403);
  });

  it("only members", async () => {
    expect((await set("ghost", true)).statusCode).toBe(404);
  });

  it("keeps the list within the limit", async () => {
    const ids = Array.from({ length: 200 }, (_, i) => `u${i}`);
    s.store.put(T, seedTeam({ memberIds: [...ids, "owner", "p1"], statKeepers: ids }));
    expect((await set("p1", true)).statusCode).toBe(412);
  });
});

describe("transfer ownership (transferOwnership)", () => {
  beforeEach(() => s.store.put(T, seedTeam()));

  it("makes another member the owner and the old owner a player", async () => {
    expect((await s.call("POST", "/v1/teams/t1/owner", "owner", { uid: "p1" })).statusCode).toBe(200);
    expect(team().ownerId).toBe("p1");
    expect(team().members).toMatchObject({ p1: "owner", owner: "player" });
  });

  it("only the owner", async () => {
    expect((await s.call("POST", "/v1/teams/t1/owner", "coach", { uid: "p1" })).statusCode).toBe(403);
  });

  it("not to themself, and only to a member", async () => {
    expect((await s.call("POST", "/v1/teams/t1/owner", "owner", { uid: "owner" })).statusCode).toBe(400);
    expect((await s.call("POST", "/v1/teams/t1/owner", "owner", { uid: "ghost" })).statusCode).toBe(404);
  });
});

describe("custom roles (setRoles)", () => {
  beforeEach(() => s.store.put(T, seedTeam({ orgRoles: { x: "y" } })));
  const roles = {
    a: { name: " Coach ", color: 1, position: 0, perms: ["keepStats", "manageTeam"] },
    b: { name: "Chat", perms: ["manageChats"] },
  };

  it("saves roles, cleans who has them, and works out memberPerms itself", async () => {
    const res = await s.call("PUT", "/v1/teams/t1/roles", "owner", {
      roles,
      memberRoles: { p1: ["b", "a", "gone"], ghost: ["a"], mgr: [] },
    });
    expect(res.statusCode).toBe(200);
    const t = team();
    expect(t.roles).toEqual({
      a: { name: "Coach", color: 1, position: 0, perms: ["manageTeam", "keepStats"] },
      b: { name: "Chat", color: 0, position: 0, perms: ["manageChats"] },
    });
    expect(t.memberRoles).toEqual({ p1: ["a", "b"] });
    expect(t.memberPerms).toEqual({ p1: ["manageTeam", "manageChats", "keepStats"] });
    // Tiers and the community's role copies are left alone.
    expect(t.members).toEqual(seedTeam().members);
    expect(t.orgRoles).toEqual({ x: "y" });
  });

  it("never takes memberPerms from the body", async () => {
    const res = await s.call("PUT", "/v1/teams/t1/roles", "owner", { roles, memberRoles: {}, memberPerms: { p1: ["manageTeam"] } });
    expect(res.statusCode).toBe(400);
  });

  it("only the owner", async () => {
    expect((await s.call("PUT", "/v1/teams/t1/roles", "coach", { roles, memberRoles: {} })).statusCode).toBe(403);
  });

  it("at most 50 roles, with known permissions", async () => {
    const many = Object.fromEntries(Array.from({ length: 51 }, (_, i) => [`r${i}`, { name: `R${i}` }]));
    expect((await s.call("PUT", "/v1/teams/t1/roles", "owner", { roles: many, memberRoles: {} })).statusCode).toBe(400);
    const bad = { a: { name: "A", perms: ["everything"] } };
    expect((await s.call("PUT", "/v1/teams/t1/roles", "owner", { roles: bad, memberRoles: {} })).statusCode).toBe(400);
  });
});

describe("per-person permissions (setMemberPermissions, API only)", () => {
  beforeEach(() => s.store.put(T, seedTeam()));
  const set = (who: string, by: string, perms: string[]) => s.call("PUT", `/v1/teams/t1/members/${who}/permissions`, by, { perms });

  it("the owner gives a player a preset's permissions; memberPerms adds them to their roles'", async () => {
    expect((await set("mgr", "owner", ["moderate", "manageChats", "manageEvents", "keepStats"])).statusCode).toBe(200);
    const t = team();
    expect(t.memberGrants).toEqual({ mgr: ["manageChats", "manageEvents", "moderate", "keepStats"] });
    expect(t.memberPerms).toEqual({ mgr: ["manageMembers", "manageChats", "manageEvents", "moderate", "keepStats"] });
  });

  it("a role save keeps them", async () => {
    await set("p1", "owner", ["manageEvents"]);
    await s.call("PUT", "/v1/teams/t1/roles", "owner", { roles: { r1: { name: "Manager", perms: ["manageMembers"] } }, memberRoles: {} });
    expect(team().memberGrants).toEqual({ p1: ["manageEvents"] });
    expect(team().memberPerms).toEqual({ p1: ["manageEvents"] });
  });

  it("[] takes them away, and turning Keep stats off ends stats access too", async () => {
    await set("p1", "owner", ["moderate"]);
    expect(team().statKeepers).toEqual([]);
    await set("p1", "owner", []);
    expect(team().memberGrants).toEqual({});
    expect(team().memberPerms).toEqual({ mgr: ["manageMembers"] });
  });

  it("only the owner: not a coach, nor someone with manageMembers, nor for themself", async () => {
    expect((await set("p1", "coach", ["moderate"])).statusCode).toBe(403);
    expect((await set("p1", "mgr", ["moderate"])).statusCode).toBe(403);
    expect((await set("mgr", "mgr", ["manageTeam"])).statusCode).toBe(403);
    expect(team().memberGrants).toBeUndefined();
  });

  it("never the owner's own, nor a legacy coach's", async () => {
    expect((await set("owner", "owner", [])).statusCode).toBe(412);
    expect((await set("coach", "owner", [])).statusCode).toBe(412);
  });

  it("known permissions only; groups keep no stats; members only", async () => {
    expect((await set("p1", "owner", ["owner"])).statusCode).toBe(400);
    expect((await set("ghost", "owner", ["moderate"])).statusCode).toBe(404);
    s.store.put(T, group());
    expect((await set("p1", "owner", ["keepStats"])).statusCode).toBe(400);
    expect((await set("p1", "owner", ["moderate"])).statusCode).toBe(200);
  });

  it("go when the member leaves, so rejoining doesn't bring them back", async () => {
    await set("p1", "owner", ["manageTeam"]);
    expect((await s.call("DELETE", "/v1/teams/t1/members/p1", "p1")).statusCode).toBe(200);
    expect(team().memberGrants).toEqual({});
    expect(team().memberPerms).not.toHaveProperty("p1");
  });

  it("a manageMembers admin can't remove someone who has their own permissions", async () => {
    await set("p1", "owner", ["moderate"]);
    expect((await s.call("DELETE", "/v1/teams/t1/members/p1", "mgr")).statusCode).toBe(403);
  });
});

describe("edit details (editDetails) and the listing", () => {
  const edit = (body: object, by = "owner") => s.call("PATCH", "/v1/teams/t1", by, body);

  it("saves the details and rewrites the listing to match", async () => {
    s.store.put(T, seedTeam({ official: true }));
    s.store.put("teamDirectory/t1", { name: "The Haze", division: "open" });
    expect((await edit({ name: "The Haze", level: "college", city: "Dallas", division: "open" })).statusCode).toBe(200);
    expect(team()).toMatchObject({ name: "The Haze", level: "college", city: "Dallas" });
    expect(s.store.doc("teamDirectory/t1")).toEqual({
      name: "The Haze",
      division: "open",
      level: "college",
      city: "Dallas",
      official: true,
      keywords: searchKeywords("The Haze Dallas"),
    });
  });

  it("manageTeam admins only", async () => {
    s.store.put(T, seedTeam());
    expect((await edit({ name: "X", level: "club" }, "mgr")).statusCode).toBe(403);
    expect((await edit({ name: "X", level: "club" }, "coach")).statusCode).toBe(200);
  });

  it("the division never changes", async () => {
    s.store.put(T, seedTeam());
    expect((await edit({ name: "The Haze", level: "club", division: "mixed" })).statusCode).toBe(412);
  });

  it("only groups have group fields", async () => {
    s.store.put(T, seedTeam());
    expect((await edit({ name: "The Haze", level: "club", description: "x" })).statusCode).toBe(400);
  });

  it("a group's fields; a private group's listing hides its location", async () => {
    s.store.put(T, group());
    const loc = { address: "Park", lat: 1, lng: 2 };
    const res = await edit({ name: "Austin Pickup", level: "pickup", city: "Austin", description: "Tue", requiresApproval: true, location: loc });
    expect(res.statusCode).toBe(200);
    expect(team()).toMatchObject({ description: "Tue", requiresApproval: true, location: loc, kind: "community" });
    expect(s.store.doc("teamDirectory/t1")).toMatchObject({ kind: "community", requiresApproval: true, location: null });
  });

  it("a new name must be free", async () => {
    s.store.put(T, seedTeam());
    s.store.put("teamDirectory/t1", { name: "The Haze" });
    s.teams.listings.push({ id: "t2", name: "Ring", kind: "team", division: "open", keywords: searchKeywords("Ring") });
    const res = await edit({ name: "Ring", level: "club" });
    expect(res.statusCode).toBe(409);
    expect(err(res).message).toBe('There\'s already a Open team called "Ring". Pick a different name.');
  });

  it("keeping its own name isn't a clash", async () => {
    s.store.put(T, seedTeam());
    s.teams.listings.push({ id: "t1", name: "The Haze", kind: "team", division: "open", keywords: searchKeywords("The Haze") });
    expect((await edit({ name: "The Haze", level: "club" })).statusCode).toBe(200);
  });

  it("publishes a listing for an admin", async () => {
    s.store.put(T, seedTeam());
    expect((await s.call("PUT", "/v1/teams/t1/listing", "p1", {})).statusCode).toBe(403);
    expect((await s.call("PUT", "/v1/teams/t1/listing", "owner", {})).statusCode).toBe(200);
    expect(s.store.doc("teamDirectory/t1")).toMatchObject({ name: "The Haze", keywords: searchKeywords("The Haze Austin") });
  });
});

describe("sections (setSections)", () => {
  const put = (body: object, by = "owner") => s.call("PUT", "/v1/teams/t1/sections", by, body);

  it("the owner turns a section on, keeping the others as they were", async () => {
    s.store.put(T, seedTeam({ sections: { playbook: false, videos: false, stats: false, meetings: false } }));
    expect((await put({ playbook: true })).statusCode).toBe(200);
    expect(team().sections).toEqual({ playbook: true, videos: false, stats: false, meetings: false });
    expect((await put({ stats: true, meetings: true })).statusCode).toBe(200);
    expect(team().sections).toEqual({ playbook: true, videos: false, stats: true, meetings: true });
  });

  it("a team from before the switches (nothing stored) can turn one off", async () => {
    s.store.put(T, seedTeam());
    expect((await put({ videos: false })).statusCode).toBe(200);
    expect(team().sections).toEqual({ videos: false });
  });

  it("the owner only", async () => {
    s.store.put(T, seedTeam());
    expect((await put({ playbook: true }, "coach")).statusCode).toBe(403);
    expect((await put({ playbook: true }, "p1")).statusCode).toBe(403);
    expect((await put({ playbook: true }, "stranger")).statusCode).toBe(403);
  });

  it("only the four optional sections, and at least one", async () => {
    s.store.put(T, seedTeam());
    expect((await put({ chat: false })).statusCode).toBe(400);
    expect((await put({ playbook: "yes" })).statusCode).toBe(400);
    expect((await put({})).statusCode).toBe(400);
  });

  it("groups and communities have none to switch", async () => {
    s.store.put(T, group());
    expect((await put({ playbook: true })).statusCode).toBe(412);
  });

  it("a missing team is not found", async () => {
    expect((await put({ playbook: true })).statusCode).toBe(404);
  });
});

describe("public team page (setPublicPage)", () => {
  const put = (body: object, by = "owner") => s.call("PUT", "/v1/teams/t1/public-page", by, body);
  const listing = () => s.store.doc("teamDirectory/t1")!;

  it("an admin turns it off and on, the listing with it", async () => {
    s.store.put(T, seedTeam());
    expect((await put({ public: false }, "coach")).statusCode).toBe(200);
    expect(team().publicPage).toBe(false);
    expect(listing()).toMatchObject({ name: "The Haze", city: "Austin", publicPage: false });
    expect((await put({ public: true })).statusCode).toBe(200);
    // On is the default: nothing stored.
    expect("publicPage" in team()).toBe(false);
    expect("publicPage" in listing()).toBe(false);
  });

  it("a member granted manageTeam may; players, other managers and outsiders can't", async () => {
    s.store.put(T, seedTeam({ memberPerms: { mgr: ["manageMembers"], p1: ["manageTeam"] } }));
    expect((await put({ public: false }, "p1")).statusCode).toBe(200);
    for (const by of ["mgr", "old", "stranger"]) expect((await put({ public: true }, by)).statusCode).toBe(403);
    expect(team().publicPage).toBe(false);
  });

  it("editing the details keeps it off in the listing", async () => {
    s.store.put(T, seedTeam({ publicPage: false }));
    s.store.put("teamDirectory/t1", { name: "The Haze", publicPage: false });
    expect((await s.call("PATCH", "/v1/teams/t1", "owner", { name: "The Haze", level: "club", city: "Dallas" })).statusCode).toBe(200);
    expect(listing()).toMatchObject({ city: "Dallas", publicPage: false });
  });

  it("only a boolean", async () => {
    s.store.put(T, seedTeam());
    expect((await put({ public: "no" })).statusCode).toBe(400);
    expect((await put({})).statusCode).toBe(400);
    expect((await put({ public: false, extra: 1 })).statusCode).toBe(400);
  });

  it("groups and communities use approval instead", async () => {
    s.store.put(T, group());
    expect((await put({ public: false })).statusCode).toBe(412);
  });

  it("a missing team is not found", async () => {
    expect((await put({ public: false })).statusCode).toBe(404);
  });
});

describe("allow join requests (setAllowJoinRequests, F26)", () => {
  const put = (body: object, by = "owner") => s.call("PUT", "/v1/teams/t1/allow-join-requests", by, body);
  const listing = () => s.store.doc("teamDirectory/t1")!;

  it("off by default; an admin turns it on and off, the listing with it", async () => {
    s.store.put(T, seedTeam());
    expect((await put({ on: true }, "coach")).statusCode).toBe(200);
    expect(team().allowJoinRequests).toBe(true);
    expect(listing()).toMatchObject({ name: "The Haze", allowJoinRequests: true });
    s.store.put("teams/t1/joinRequests/a", { name: "A" });
    s.store.put("teams/t1/joinRequests/b", { name: "B" });
    expect((await put({ on: false })).statusCode).toBe(200);
    expect("allowJoinRequests" in team()).toBe(false);
    expect("allowJoinRequests" in listing()).toBe(false);
    // Off declines the requests waiting.
    expect(s.store.doc("teams/t1/joinRequests/a")).toBeUndefined();
    expect(s.store.doc("teams/t1/joinRequests/b")).toBeUndefined();
  });

  it("manageTeam only: not manageMembers, players or outsiders", async () => {
    s.store.put(T, seedTeam({ memberPerms: { mgr: ["manageMembers"], p1: ["manageTeam"] } }));
    expect((await put({ on: true }, "p1")).statusCode).toBe(200);
    for (const by of ["mgr", "old", "stranger"]) expect((await put({ on: false }, by)).statusCode).toBe(403);
    expect(team().allowJoinRequests).toBe(true);
  });

  it("teams only: not groups (they approve who joins) nor a league's team; a boolean", async () => {
    s.store.put(T, group());
    expect((await put({ on: true })).statusCode).toBe(412);
    s.store.put(T, seedTeam({ leagueId: "lg1" }));
    expect((await put({ on: true })).statusCode).toBe(412);
    s.store.put(T, seedTeam());
    expect((await put({ on: "yes" })).statusCode).toBe(400);
  });

  it("editing the details keeps it in the listing", async () => {
    s.store.put(T, seedTeam({ allowJoinRequests: true }));
    expect((await s.call("PATCH", "/v1/teams/t1", "owner", { name: "The Haze", level: "club", city: "Dallas" })).statusCode).toBe(200);
    expect(listing()).toMatchObject({ city: "Dallas", allowJoinRequests: true });
  });
});

describe("team join requests (F26)", () => {
  beforeEach(() => s.store.put(T, seedTeam({ allowJoinRequests: true, level: "college" })));
  const R = "teams/t1/joinRequests/new";

  it("a signed-in outsider asks; a manageMembers admin approves as a player", async () => {
    s.users.records.set("new", { name: "Nia" });
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "new", {})).statusCode).toBe(200);
    expect(s.store.doc(R)).toEqual({ name: "Nia", createdAt: new Date(now) });
    expect((await s.call("POST", "/v1/teams/t1/join-requests/new/approve", "mgr", {})).statusCode).toBe(200);
    expect(team().members).toMatchObject({ new: "player" });
    expect(team().memberNames).toMatchObject({ new: "Nia" });
    expect(s.store.doc(R)).toBeUndefined();
  });

  it("not while muted, not from a member", async () => {
    s.store.put("limits/new", { mutedUntil: new Date(now + 60_000) });
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "new", {})).statusCode).toBe(429);
    expect((await s.call("POST", "/v1/teams/t1/join-requests", "p1", {})).statusCode).toBe(409);
  });

  it("players can't approve or decline; the asker cancels their own", async () => {
    s.store.put(R, { name: "Nia" });
    expect((await s.call("POST", "/v1/teams/t1/join-requests/new/approve", "p1", {})).statusCode).toBe(403);
    expect((await s.call("DELETE", "/v1/teams/t1/join-requests/new", "p1")).statusCode).toBe(403);
    expect((await s.call("DELETE", "/v1/teams/t1/join-requests/new", "new")).statusCode).toBe(200);
    expect(s.store.doc(R)).toBeUndefined();
  });

  it("a request from someone who joined since just clears", async () => {
    s.store.put(R, { name: "Pat" });
    s.store.put("teams/t1/joinRequests/p1", { name: "Pat" });
    expect((await s.call("POST", "/v1/teams/t1/join-requests/p1/approve", "owner", {})).statusCode).toBe(200);
    expect(s.store.doc("teams/t1/joinRequests/p1")).toBeUndefined();
    expect(team().members).toMatchObject({ p1: "player" });
  });
});

describe("invite codes (inviteCodes create)", () => {
  const mint = (body: object, by = "owner") => s.call("POST", "/v1/invite-codes", by, body);

  it("mints a 6-character code for 45 seconds", async () => {
    s.store.put(T, seedTeam());
    const res = await mint({ teamId: "t1", ttl: 45 });
    expect(res.statusCode).toBe(201);
    const { code, teamId, expiresAt } = res.json();
    expect(code).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    expect(teamId).toBe("t1");
    expect(expiresAt).toBe(new Date(now + 45_000).toISOString());
    expect(s.store.doc(`inviteCodes/${code}`)).toEqual({
      teamId: "t1",
      createdBy: "owner",
      createdAt: new Date(now),
      ttl: 45,
      expiresAt: new Date(now + 45_000),
    });
  });

  it("mints 20-character link tokens for the allowed lifetimes only", async () => {
    s.store.put(T, seedTeam());
    const res = await mint({ teamId: "t1", ttl: 604800 });
    expect(res.json().code).toMatch(/^[A-Z0-9]{20}$/);
    expect((await mint({ teamId: "t1", ttl: 100 })).statusCode).toBe(400);
  });

  it("manageMembers admins only", async () => {
    s.store.put(T, seedTeam());
    expect((await mint({ teamId: "t1", ttl: 45 }, "p1")).statusCode).toBe(403);
    expect((await mint({ teamId: "t1", ttl: 45 }, "mgr")).statusCode).toBe(201);
  });

  it("not for a community group; fine for a school or club community", async () => {
    s.store.put(T, group());
    expect((await mint({ teamId: "t1", ttl: 45 })).statusCode).toBe(412);
    s.store.put(T, group({ kind: "organization" }));
    expect((await mint({ teamId: "t1", ttl: 45 })).statusCode).toBe(201);
  });

  it("tries a fresh code when one is taken", async () => {
    s.store.put(T, seedTeam());
    const codes = ["TAKEN1", "FRESH2"];
    const { MembershipService } = await import("../src/teams/membership.js");
    const m = new MembershipService(s.store, s.users, s.teams, () => now, () => codes.shift()!);
    s.store.put("inviteCodes/TAKEN1", { teamId: "other" });
    const out = await m.createInviteCode({ uid: "owner" }, { teamId: "t1", ttl: 45 });
    expect(out.code).toBe("FRESH2");
    expect(s.store.doc("inviteCodes/TAKEN1")).toEqual({ teamId: "other" });
  });
});

describe("communities", () => {
  const O = "teams/org1";
  const org = (over: Record<string, unknown> = {}) =>
    group({ name: "St. Mary's", kind: "organization", requiresApproval: true, linkedTeams: {}, ...over });
  const L = "teams/org1/linkRequests/t1";

  beforeEach(() => {
    s.store.put(T, seedTeam());
    s.store.put(O, org());
  });

  describe("asking to join (setOrg, linkRequests create)", () => {
    it("names the community from its doc and records the request", async () => {
      s.users.records.set("coach", { name: "Cody C" });
      const res = await s.call("PUT", "/v1/teams/t1/community", "coach", { orgId: "org1" });
      expect(res.statusCode).toBe(200);
      expect(team()).toMatchObject({ orgId: "org1", orgName: "St. Mary's" });
      expect(s.store.doc(L)).toEqual({
        teamName: "The Haze",
        division: "open",
        requestedBy: "coach",
        requestedByName: "Cody C",
        createdAt: new Date(now),
      });
    });

    it("the team's manageTeam admins only", async () => {
      expect((await s.call("PUT", "/v1/teams/t1/community", "mgr", { orgId: "org1" })).statusCode).toBe(403);
    });

    it("teams only, into a school or club community only, not itself", async () => {
      s.store.put("teams/g1", group());
      expect((await s.call("PUT", "/v1/teams/g1/community", "owner", { orgId: "org1" })).statusCode).toBe(412);
      expect((await s.call("PUT", "/v1/teams/t1/community", "owner", { orgId: "g1" })).statusCode).toBe(404);
      expect((await s.call("PUT", "/v1/teams/t1/community", "owner", { orgId: "t1" })).statusCode).toBe(400);
    });

    it("never writes the fields the communities functions own", async () => {
      await s.call("PUT", "/v1/teams/t1/community", "owner", { orgId: "org1" });
      expect(team()).not.toHaveProperty("orgLinked");
      expect(team()).not.toHaveProperty("orgMembers");
    });
  });

  it("leaving clears orgId and withdraws a pending request", async () => {
    s.store.put(T, seedTeam({ orgId: "org1", orgName: "St. Mary's" }));
    s.store.put(L, { teamName: "The Haze" });
    expect((await s.call("DELETE", "/v1/teams/t1/community", "p1")).statusCode).toBe(403);
    expect((await s.call("DELETE", "/v1/teams/t1/community", "owner")).statusCode).toBe(200);
    expect(team()).toMatchObject({ orgId: null, orgName: "" });
    expect(s.store.doc(L)).toBeUndefined();
  });

  describe("the community's side (editLinks)", () => {
    beforeEach(() => s.store.put(L, { teamName: "The Haze", division: "open", requestedBy: "owner" }));

    it("accepting lists the team with sorted roles and clears the request", async () => {
      const res = await s.call("POST", "/v1/teams/org1/link-requests/t1/accept", "owner", { roles: ["z", "a"] });
      expect(res.statusCode).toBe(200);
      expect(s.store.doc(O)!.linkedTeams).toEqual({ t1: { name: "The Haze", division: "open", roles: ["a", "z"] } });
      expect(s.store.doc(L)).toBeUndefined();
    });

    it("the community's manageTeam admins only", async () => {
      expect((await s.call("POST", "/v1/teams/org1/link-requests/t1/accept", "mgr", { roles: [] })).statusCode).toBe(403);
    });

    it("at most 20 linked teams", async () => {
      const full = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`x${i}`, { name: "X", roles: [] }]));
      s.store.put(O, org({ linkedTeams: full }));
      expect((await s.call("POST", "/v1/teams/org1/link-requests/t1/accept", "owner", { roles: [] })).statusCode).toBe(412);
    });

    it("only a school or club community links teams", async () => {
      s.store.put(O, group());
      expect((await s.call("POST", "/v1/teams/org1/link-requests/t1/accept", "owner", { roles: [] })).statusCode).toBe(404);
    });

    it("either side's admins decline; others can't", async () => {
      expect((await s.call("DELETE", "/v1/teams/org1/link-requests/t1", "p1")).statusCode).toBe(403);
      expect((await s.call("DELETE", "/v1/teams/org1/link-requests/t1", "coach")).statusCode).toBe(200);
      expect(s.store.doc(L)).toBeUndefined();
    });

    it("changes a linked team's roles, and unlinks it", async () => {
      s.store.put(O, org({ linkedTeams: { t1: { name: "The Haze", division: "open", roles: ["a"] } } }));
      expect((await s.call("PUT", "/v1/teams/org1/linked-teams/t1", "owner", { roles: ["b"] })).statusCode).toBe(200);
      expect(s.store.doc(O)!.linkedTeams).toEqual({ t1: { name: "The Haze", division: "open", roles: ["b"] } });
      expect((await s.call("PUT", "/v1/teams/org1/linked-teams/t9", "owner", { roles: [] })).statusCode).toBe(404);
      expect((await s.call("DELETE", "/v1/teams/org1/linked-teams/t1", "p1")).statusCode).toBe(403);
      expect((await s.call("DELETE", "/v1/teams/org1/linked-teams/t1", "owner")).statusCode).toBe(200);
      expect(s.store.doc(O)!.linkedTeams).toEqual({});
    });
  });

  describe("a new team in a community", () => {
    const body = { name: "Haze JV", division: "open", level: "youth", city: "Austin", roles: ["r1"] };

    it("creates the team, owned by the caller, named in and listed by the community", async () => {
      s.users.records.set("owner", { name: "Olive O" });
      const res = await s.call("POST", "/v1/teams/org1/linked-teams", "owner", body);
      expect(res.statusCode).toBe(201);
      const id = res.json().id;
      expect(s.store.doc(`teams/${id}`)).toMatchObject({
        name: "Haze JV",
        ownerId: "owner",
        members: { owner: "owner" },
        memberNames: { owner: "Olive O" },
        orgId: "org1",
        orgName: "St. Mary's",
        // A new team starts simple: the optional sections off.
        sections: { playbook: false, videos: false, stats: false, meetings: false },
      });
      expect(s.store.doc(`teamDirectory/${id}`)).toBeDefined();
      expect(s.store.doc(`teams/${id}/chats/general`)).toBeDefined();
      expect(s.store.doc(O)!.linkedTeams).toEqual({ [id]: { name: "Haze JV", division: "open", roles: ["r1"] } });
    });

    it("the community's manageTeam admins only", async () => {
      expect((await s.call("POST", "/v1/teams/org1/linked-teams", "p1", body)).statusCode).toBe(403);
    });

    it("checks the name and the flood mute", async () => {
      s.teams.listings.push({ id: "x", name: "Haze JV", kind: "team", division: "open", keywords: searchKeywords("Haze JV") });
      expect((await s.call("POST", "/v1/teams/org1/linked-teams", "owner", body)).statusCode).toBe(409);
      s.teams.listings.length = 0;
      s.store.put("limits/owner", { mutedUntil: new Date(now + 60_000) });
      expect((await s.call("POST", "/v1/teams/org1/linked-teams", "owner", body)).statusCode).toBe(429);
    });
  });
});

describe("club teams are for players 16 and over", () => {
  // now is 2026-11-11 12:00 UTC; ages count on the date in UTC+14, 2026-11-12.
  const turns16Today = "2010-11-12";
  const turns16Tomorrow = "2010-11-13";
  const tooYoung = { code: "failed_precondition", message: "Club teams are for players 16 and over." };
  const noBirthDate = { code: "failed_precondition", message: "Add your date of birth in About you to join a club team." };
  const code = () =>
    s.store.put("inviteCodes/ABC234", { teamId: "t1", createdBy: "owner", createdAt: new Date(now - 10_000), ttl: 45, expiresAt: new Date(now + 35_000) });
  const invite = (uid: string) => s.store.put(`users/${uid}/teamInvites/t1`, { teamName: "The Haze", kind: "team" });
  const born = (uid: string, date: string) => seedBirthDate(s.store, s.cipher, uid, date);

  beforeEach(() => s.store.put(T, seedTeam()));

  describe("joining with a code or link", () => {
    it("takes someone on their 16th birthday", async () => {
      code();
      await born("kid", turns16Today);
      expect((await s.call("POST", "/v1/teams/join", "kid", { code: "ABC234" })).statusCode).toBe(200);
      expect(team().memberIds).toContain("kid");
    });

    it("refuses the day before; nothing is written", async () => {
      code();
      await born("kid", turns16Tomorrow);
      const res = await s.call("POST", "/v1/teams/join", "kid", { code: "ABC234" });
      expect(res.statusCode).toBe(412);
      expect(err(res)).toEqual(tooYoung);
      expect(team().memberIds).not.toContain("kid");
      expect(s.store.doc("teams/t1/joins/kid")).toBeUndefined();
    });

    it("needs a date of birth on file", async () => {
      code();
      const res = await s.call("POST", "/v1/teams/join", "nobirth", { code: "ABC234" });
      expect(res.statusCode).toBe(412);
      expect(err(res)).toEqual(noBirthDate);
    });

    it("never decrypts the date of birth of someone already on the team", async () => {
      code();
      // p1 has no date on file and is under no check: existing members stay.
      expect((await s.call("POST", "/v1/teams/join", "p1", { code: "ABC234" })).statusCode).toBe(200);
      expect(s.cipher.calls.open).toBe(0);
    });

    it("leaves other levels alone", async () => {
      for (const level of ["college", "youth", "league", "pickup"]) {
        s.store.put(T, seedTeam({ level }));
        code();
        await born("kid", "2012-06-01");
        expect((await s.call("POST", "/v1/teams/join", "kid", { code: "ABC234" })).statusCode).toBe(200);
        expect((await s.call("POST", "/v1/teams/join", "nobirth", { code: "ABC234" })).statusCode).toBe(200);
      }
      expect(s.cipher.calls.open).toBe(0);
    });
  });

  describe("invites", () => {
    it("anyone may be invited (their age is private), and the check is at accept", async () => {
      expect((await s.call("POST", "/v1/teams/t1/invites", "owner", { uid: "kid" })).statusCode).toBe(200);
      await born("kid", turns16Tomorrow);
      const res = await s.call("POST", "/v1/me/team-invites/t1/accept", "kid", {});
      expect(res.statusCode).toBe(412);
      expect(err(res)).toEqual(tooYoung);
      expect(team().memberIds).not.toContain("kid");
      // The invite stays, to accept once they're 16 (or decline).
      expect(s.store.doc("users/kid/teamInvites/t1")).toBeDefined();
    });

    it("accepting on the 16th birthday joins", async () => {
      invite("kid");
      await born("kid", turns16Today);
      expect((await s.call("POST", "/v1/me/team-invites/t1/accept", "kid", {})).statusCode).toBe(200);
      expect(team().members).toMatchObject({ kid: "player" });
    });

    it("accepting needs a date of birth on file", async () => {
      invite("nobirth");
      expect(err(await s.call("POST", "/v1/me/team-invites/t1/accept", "nobirth", {}))).toEqual(noBirthDate);
    });

    it("a group's invite is unaffected", async () => {
      s.store.put(T, group({ level: "club" }));
      invite("kid");
      await born("kid", "2012-06-01");
      expect((await s.call("POST", "/v1/me/team-invites/t1/accept", "kid", {})).statusCode).toBe(200);
    });
  });

  describe("join requests (F26)", () => {
    beforeEach(() => s.store.put(T, seedTeam({ allowJoinRequests: true })));
    const ask = (uid: string) => s.call("POST", "/v1/teams/t1/join-requests", uid, {});
    const approve = (uid: string) => s.call("POST", `/v1/teams/t1/join-requests/${uid}/approve`, "mgr", {});

    it("someone under 16 is told when they ask, and nothing is written", async () => {
      await born("kid", turns16Tomorrow);
      const res = await ask("kid");
      expect(res.statusCode).toBe(412);
      expect(err(res)).toEqual(tooYoung);
      expect(s.store.doc("teams/t1/joinRequests/kid")).toBeUndefined();
    });

    it("asking needs a date of birth on file", async () => {
      expect(err(await ask("nobirth"))).toEqual(noBirthDate);
    });

    it("approving checks again: a request from before is refused, naming them", async () => {
      s.store.put("teams/t1/joinRequests/kid", { name: "Kid" });
      await born("kid", turns16Tomorrow);
      const res = await approve("kid");
      expect(res.statusCode).toBe(412);
      expect(err(res).message).toContain("Kid");
      expect(team().memberIds).not.toContain("kid");
      // Still there, to approve once they're 16 or decline.
      expect(s.store.doc("teams/t1/joinRequests/kid")).toBeDefined();
      s.store.put("teams/t1/joinRequests/nobirth", { name: "Nobody" });
      expect((await approve("nobirth")).statusCode).toBe(412);
    });

    it("on their 16th birthday they ask and are approved", async () => {
      await born("kid", turns16Today);
      expect((await ask("kid")).statusCode).toBe(200);
      expect((await approve("kid")).statusCode).toBe(200);
      expect(team().members).toMatchObject({ kid: "player" });
      expect(s.store.doc("teams/t1/joinRequests/kid")).toBeUndefined();
    });

    it("other levels take anyone", async () => {
      s.store.put(T, seedTeam({ allowJoinRequests: true, level: "college" }));
      await born("kid", "2012-06-01");
      expect((await ask("kid")).statusCode).toBe(200);
      expect((await approve("kid")).statusCode).toBe(200);
    });
  });

  it("a group that approves who joins takes anyone, club level or not", async () => {
    s.store.put("teams/t1/joinRequests/kid", { name: "Kid" });
    s.store.put(T, group({ level: "club", requiresApproval: true }));
    await born("kid", "2012-06-01");
    expect((await s.call("POST", "/v1/teams/t1/join-requests/kid/approve", "mgr", {})).statusCode).toBe(200);
    expect(team().memberIds).toContain("kid");
  });

  // SEC-4: level only changes through PATCH /v1/teams/:id, and a switch to
  // club re-checks everyone on the team (the rules no longer take the write).
  describe("changing a team's level (SEC-4)", () => {
    const patch = (level: unknown, uid = "owner") =>
      s.call("PATCH", "/v1/teams/t1", uid, { name: "The Haze", level, city: "Austin" });
    const adults = () => Promise.all(["owner", "coach", "p1", "mgr", "old"].map((u) => born(u, "1990-01-01")));
    const withKid = (extra: Record<string, unknown> = {}) => {
      const base = seedTeam();
      s.store.put(T, seedTeam({ level: "youth", members: { ...base.members, kid: "player" }, memberIds: [...base.memberIds, "kid"], ...extra }));
    };
    const refused = (res: { statusCode: number; json(): unknown }) => {
      expect(res.statusCode).toBe(412);
      expect(err(res).code).toBe("failed_precondition");
      expect(err(res).message).toMatch(/can't switch to the club level/);
      expect(team().level).toBe("youth");
    };

    it("lets a manager switch to club when everyone is 16 or over", async () => {
      withKid();
      await adults();
      await born("kid", turns16Today);
      expect((await patch("club")).statusCode).toBe(200);
      expect(team()).toMatchObject({ level: "club" });
      expect(s.store.doc("teamDirectory/t1")).toMatchObject({ level: "club" });
    });

    it("refuses when a member is under 16; nothing is written", async () => {
      withKid();
      await adults();
      await born("kid", "2012-06-01");
      const res = await patch("club");
      refused(res);
      expect(err(res).message).toContain("1 person on it is under 16");
      expect(s.store.doc("teamDirectory/t1")).toBeUndefined();
    });

    it("refuses the day before a member's 16th birthday", async () => {
      withKid();
      await adults();
      await born("kid", turns16Tomorrow);
      refused(await patch("club"));
    });

    it("refuses when a member has no date of birth", async () => {
      withKid();
      await adults();
      refused(await patch("club"));
    });

    it("counts everyone who fails, without naming them", async () => {
      withKid();
      const res = await patch("club");
      expect(res.statusCode).toBe(412);
      expect(err(res).message).toContain("6 people on it are under 16");
      expect(err(res).message).not.toContain("kid");
    });

    it("checks an account linked to a roster spot, even if they left the team", async () => {
      s.store.put(T, seedTeam({ level: "youth" }));
      await adults();
      s.store.put("teams/t1/roster/r1", { name: "Left", position: "cutter", userId: "gone" });
      await born("gone", "2013-01-01");
      refused(await patch("club"));
    });

    it("ignores roster spots with no account", async () => {
      s.store.put(T, seedTeam({ level: "youth" }));
      await adults();
      s.store.put("teams/t1/roster/r1", { name: "Walk-on", position: "cutter" });
      expect((await patch("club")).statusCode).toBe(200);
    });

    it("refuses without the personal-details key (fails closed)", async () => {
      const store = new FakeStore(() => now);
      const app = buildApp({ verifier: new FakeVerifier(), users: new FakeUsers(), teams: new FakeTeamRepository(), store, now: () => now });
      store.put(T, seedTeam({ level: "youth" }));
      const res = await app.inject({
        method: "PATCH",
        url: "/v1/teams/t1",
        headers: { authorization: "Bearer token:owner:Name owner" },
        payload: { name: "The Haze", level: "club", city: "Austin" },
      });
      expect(res.statusCode).toBe(503);
      expect(store.doc(T)!.level).toBe("youth");
    });

    it("refuses a non-manager, even when every age would pass", async () => {
      s.store.put(T, seedTeam({ level: "youth" }));
      await adults();
      for (const by of ["mgr", "p1", "old", "stranger"]) expect((await patch("club", by)).statusCode).toBe(403);
      expect(team().level).toBe("youth");
    });

    it("refuses a level that doesn't exist", async () => {
      s.store.put(T, seedTeam({ level: "youth" }));
      expect((await patch("pro")).statusCode).toBe(400);
      expect((await patch(7)).statusCode).toBe(400);
      expect((await patch(undefined)).statusCode).toBe(400);
      expect(team().level).toBe("youth");
    });

    it("changing away from club needs no age check", async () => {
      // Nobody has a date of birth on file.
      s.store.put(T, seedTeam({ level: "club" }));
      expect((await patch("college")).statusCode).toBe(200);
      expect(team().level).toBe("college");
    });

    it("moving between other levels needs no age check", async () => {
      withKid();
      expect((await patch("college")).statusCode).toBe(200);
      expect(team().level).toBe("college");
    });

    it("a team already at club keeps editing its other details", async () => {
      withKid({ level: "club" });
      expect((await patch("club")).statusCode).toBe(200);
    });

    it("a group's level is never set from the request", async () => {
      s.store.put(T, group());
      const res = await s.call("PATCH", "/v1/teams/t1", "owner", { name: "Austin Pickup", level: "club", city: "Austin" });
      expect(res.statusCode).toBe(200);
      expect(team().level).toBe("pickup");
    });
  });

  describe("a new club team in a community", () => {
    const body = { name: "Haze Club", division: "open", level: "club", city: "Austin", roles: [] };
    beforeEach(() =>
      s.store.put("teams/org1", group({ name: "St. Mary's", kind: "organization", requiresApproval: true, linkedTeams: {} })),
    );

    it("needs its creator to be 16 or over", async () => {
      await born("owner", turns16Tomorrow);
      const res = await s.call("POST", "/v1/teams/org1/linked-teams", "owner", body);
      expect(res.statusCode).toBe(412);
      expect(err(res)).toEqual(tooYoung);
      expect(s.store.doc("teams/org1")!.linkedTeams).toEqual({});
      await born("owner", turns16Today);
      expect((await s.call("POST", "/v1/teams/org1/linked-teams", "owner", body)).statusCode).toBe(201);
    });

    it("needs a date of birth on file; other levels don't", async () => {
      expect(err(await s.call("POST", "/v1/teams/org1/linked-teams", "owner", body))).toEqual(noBirthDate);
      expect((await s.call("POST", "/v1/teams/org1/linked-teams", "owner", { ...body, level: "college" })).statusCode).toBe(201);
    });
  });

  it("refuses club joins when the API has no personal-details key", async () => {
    const app = buildApp({ verifier: new FakeVerifier(), users: s.users, teams: s.teams, store: s.store, now: () => now });
    code();
    const res = await app.inject({
      method: "POST",
      url: "/v1/teams/join",
      headers: { authorization: "Bearer token:new:New" },
      payload: { code: "ABC234" },
    });
    expect(res.statusCode).toBe(503);
    expect(err(res).code).toBe("unavailable");
    expect(team().memberIds).not.toContain("new");
  });
});
