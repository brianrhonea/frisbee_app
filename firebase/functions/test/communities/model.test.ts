import { describe, expect, it } from "vitest";

import {
  holders,
  membershipUpdate,
  mirrorUpdate,
  type OrgDoc,
  planOrgChange,
  syncUpdate,
  type TeamDoc,
} from "../../src/communities/model";

const org = (extra: Partial<OrgDoc> = {}): OrgDoc => ({
  kind: "organization",
  name: "Tech",
  memberIds: ["a", "b", "c"],
  memberNames: { a: "Ann", b: "Bo", c: "Cy" },
  memberRoles: { a: ["woof"], b: ["whip"], c: ["woof", "officer"] },
  linkedTeams: { woofTeam: { name: "Woof", roles: ["woof"] } },
  ...extra,
});

const team = (extra: Partial<TeamDoc> = {}): TeamDoc => ({
  ownerId: "o",
  members: { o: "owner", c: "player" },
  memberIds: ["o", "c"],
  memberNames: { o: "Owner", c: "Cy" },
  orgId: "org",
  orgLinked: true,
  orgMembers: [],
  ...extra,
});

describe("communities", () => {
  it("finds who holds a team's roles", () => {
    expect([...holders(org(), ["woof"])].sort()).toEqual(["a", "c"]);
    expect([...holders(org(), [])]).toEqual([]);
    // Former members keep no access.
    expect([...holders(org({ memberIds: ["a"] }), ["woof"])]).toEqual(["a"]);
  });

  it("plans joins and leaves when roles change", () => {
    const after = org({ memberRoles: { a: [], b: ["whip", "woof"], c: ["woof"] } });
    expect(planOrgChange(org(), after)).toEqual([
      { teamId: "woofTeam", listed: true, all: ["b", "c"], add: ["b"], remove: ["a"], renamed: false },
    ]);
    // Unchanged, a listed team still gets a look (to catch up if it was
    // never linked), with nothing to add or remove.
    expect(planOrgChange(org(), org())).toEqual([
      { teamId: "woofTeam", listed: true, all: ["a", "c"], add: [], remove: [], renamed: false },
    ]);
  });

  it("plans a team listed or dropped", () => {
    const [listed] = planOrgChange(org({ linkedTeams: {} }), org());
    expect(listed).toMatchObject({ listed: true, all: ["a", "c"] });
    const [dropped] = planOrgChange(org(), org({ linkedTeams: {} }));
    expect(dropped).toMatchObject({ listed: false, remove: ["a", "c"] });
  });

  it("adds people as players and remembers the community added them", () => {
    const update = membershipUpdate(team(), ["a", "c"], [], { a: "Ann" });
    expect(update).toMatchObject({
      members: { o: "owner", c: "player", a: "player" },
      memberIds: ["o", "c", "a"],
      memberNames: { a: "Ann" },
      orgMembers: ["a"],
    });
  });

  it("only removes people the community added, never the owner", () => {
    const t = team({
      members: { o: "owner", a: "player", c: "player" },
      memberIds: ["o", "a", "c"],
      memberRoles: { a: ["x"] },
      memberPerms: { a: ["moderate"] },
      statKeepers: ["a"],
      orgMembers: ["a", "o"],
    });
    const update = membershipUpdate(t, [], ["a", "c", "o"], {});
    expect(update).toMatchObject({
      members: { o: "owner", c: "player" },
      memberIds: ["o", "c"],
      memberRoles: {},
      memberPerms: {},
      statKeepers: [],
      orgMembers: [],
    });
    expect(membershipUpdate(team(), [], ["c"], {})).toBeNull();
  });
});

describe("copies of community roles", () => {
  const roles = {
    cap: { perms: ["manageEvents"] },
    mine: { perms: ["moderate"] },
  };

  it("go to exactly the members holding the community role", () => {
    const t = team({
      members: { o: "owner", a: "player", c: "player" },
      memberIds: ["o", "a", "c"],
      roles,
      orgRoles: { cap: "officer" },
      memberRoles: { a: ["cap", "mine"] },
      memberPerms: { a: ["manageEvents", "moderate"] },
    });
    // c is an officer in the community; a isn't, but keeps their own role.
    expect(mirrorUpdate(t, org())).toEqual({
      memberRoles: { a: ["mine"], c: ["cap"] },
      memberPerms: { a: ["moderate"], c: ["manageEvents"] },
    });
  });

  it("change nothing when they already match, or there are none", () => {
    const t = team({
      roles,
      orgRoles: { cap: "officer" },
      memberRoles: { c: ["cap"] },
      memberPerms: { c: ["manageEvents"] },
    });
    expect(mirrorUpdate(t, org())).toBeNull();
    expect(mirrorUpdate(team(), org())).toBeNull();
  });

  it("follow people the community adds to the team", () => {
    const t = team({ roles, orgRoles: { cap: "officer" } });
    const o = org({ memberRoles: { a: ["woof", "officer"], c: ["woof"] } });
    expect(syncUpdate(t, o, ["a"], [], { a: "Ann" })).toMatchObject({
      memberIds: ["o", "c", "a"],
      memberRoles: { a: ["cap"] },
      memberPerms: { a: ["manageEvents"] },
    });
  });
});
