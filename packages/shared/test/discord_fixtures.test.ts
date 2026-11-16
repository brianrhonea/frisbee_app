// The app's Discord import mapping (apps/mobile/lib/domain/models/
// discord_import.dart) against discord.ts, on the vectors in
// fixtures/discord (written by
// apps/mobile/test/shared_fixtures/discord_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import {
  type DiscordImport,
  type ExistingFolder,
  type ExistingRoom,
  type ImportPlan,
  type ImportTeam,
  importIsEmpty,
  planFor,
  planImport,
  rolesData,
  splitPlan,
  splitTeams,
  teamChatImport,
  teamChatImportIsEmpty,
} from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

/** Ids n1, n2, ... as the app's test makes them. */
const ids = () => {
  let n = 0;
  return () => `n${++n}`;
};

/**
 * The import with its roles as they're written: the app's fixture has
 * CustomRole.toMap, which trims names, and the API writes them through
 * rolesData, which does too.
 */
const importJson = (i: DiscordImport) => ({ ...i, roles: rolesData(i.roles, {}).roles, isEmpty: importIsEmpty(i) });

describe("importing a plan matches the app (fixtures/discord/import.json)", () => {
  it.each(
    fixture<{ name: string; plan: ImportPlan; team: ImportTeam; folders: ExistingFolder[]; rooms: ExistingRoom[]; expected: unknown }>("discord/import.json")
      .cases,
  )("$name", (c) => {
    expect(importJson(planImport(c.plan, c.team, c.folders, c.rooms, ids()))).toEqual(c.expected);
  });
});

describe("splitting an import matches the app (fixtures/discord/split.json)", () => {
  it.each(
    fixture<{
      name: string;
      plan: ImportPlan;
      org: ImportTeam;
      roleIds: Record<string, string>;
      overrides: Array<[number, string | null]>;
      suggested: Array<string | null>;
      destinations: Array<string | null>;
      teams: string[];
      planFor: Record<string, unknown>;
    }>("discord/split.json").cases,
  )("$name", (c) => {
    const split = splitPlan(c.plan, c.org, c.roleIds, new Map(c.overrides));
    expect(split).toEqual({ suggested: c.suggested, destinations: c.destinations });
    expect([...splitTeams(split)]).toEqual(c.teams);
    for (const [team, part] of Object.entries(c.planFor)) {
      const p = planFor(c.plan, split, team === "null" ? null : team);
      expect({
        roles: p.roles.map((r) => r.key),
        folders: p.folders.map((f) => f.key),
        rooms: p.rooms.map((r) => r.name),
        skipped: p.skipped.length,
        skippedRoles: p.skippedRoles,
      }).toEqual(part);
    }
  });
});

describe("a linked team's share matches the app (fixtures/discord/team_chat.json)", () => {
  it.each(
    fixture<{
      name: string;
      plan: ImportPlan;
      org: ImportTeam;
      teamId: string;
      team: ImportTeam;
      roleIds: Record<string, string>;
      folders: ExistingFolder[];
      rooms: ExistingRoom[];
      expected: { import: unknown; orgRoles: Record<string, string>; isEmpty: boolean };
    }>("discord/team_chat.json").cases,
  )("$name", (c) => {
    const split = splitPlan(c.plan, c.org, c.roleIds);
    const t = teamChatImport(planFor(c.plan, split, c.teamId), c.org, c.teamId, c.team, c.roleIds, c.folders, c.rooms, ids());
    expect({ import: importJson(t.import), orgRoles: t.orgRoles, isEmpty: teamChatImportIsEmpty(t, c.team) }).toEqual(c.expected);
  });
});
