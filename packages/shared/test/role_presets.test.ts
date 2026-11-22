import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  cleanMemberGrants,
  groupRolePresets,
  memberPermsFor,
  presetMatching,
  setMemberPermissionsRequestSchema,
  teamPermissions,
  teamRolePresets,
} from "../src/index.js";

// Written by the app (test/data/shared_fixtures_test.dart: RolePreset).
const fixture = JSON.parse(readFileSync(new URL("../fixtures/role_presets.json", import.meta.url), "utf8")) as {
  team: Array<{ id: string; name: string; summary: string; perms: string[] }>;
  group: Array<{ id: string; name: string; summary: string; perms: string[] }>;
};

const plain = (list: typeof teamRolePresets) => list.map((p) => ({ id: p.id, name: p.name, summary: p.summary, perms: [...p.perms] }));

describe("role presets (F25)", () => {
  it("match the app's", () => {
    expect(plain(teamRolePresets)).toEqual(fixture.team);
    expect(plain(groupRolePresets)).toEqual(fixture.group);
  });

  it("go from no permissions to every one; groups keep no stats", () => {
    expect(teamRolePresets[0]?.perms).toEqual([]);
    expect(teamRolePresets.at(-1)?.perms).toEqual([...teamPermissions]);
    for (const p of groupRolePresets) expect(p.perms).not.toContain("keepStats");
  });

  it("name the preset with exactly those permissions, else Custom (null)", () => {
    expect(presetMatching(["keepStats", "moderate", "manageEvents", "manageChats"], false)?.name).toBe("Captain");
    expect(presetMatching([], false)?.id).toBe("member");
    expect(presetMatching(["moderate"], false)).toBeNull();
    expect(presetMatching(["manageChats", "moderate"], true)?.name).toBe("Moderator");
  });

  it("take only known permissions in a request", () => {
    expect(setMemberPermissionsRequestSchema.safeParse({ perms: ["moderate"] }).success).toBe(true);
    expect(setMemberPermissionsRequestSchema.safeParse({ perms: ["owner"] }).success).toBe(false);
    expect(setMemberPermissionsRequestSchema.safeParse({ perms: ["moderate"], uid: "x" }).success).toBe(false);
  });
});

describe("members' own permissions (memberGrants)", () => {
  it("are cleaned to members and known permissions, in order", () => {
    expect(cleanMemberGrants({ a: ["moderate", "bogus", "manageTeam"], b: [], gone: ["manageTeam"], c: "x" }, ["a", "b", "c"])).toEqual({
      a: ["manageTeam", "moderate"],
    });
    expect(cleanMemberGrants(null, ["a"])).toEqual({});
  });

  it("count in memberPerms with role permissions", () => {
    expect(memberPermsFor({ a: ["r"] }, { r: { perms: ["manageChats"] } }, { a: ["keepStats"], b: ["moderate"] })).toEqual({
      a: ["manageChats", "keepStats"],
      b: ["moderate"],
    });
  });
});
