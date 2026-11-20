import { readFileSync } from "node:fs";
import {
  cleanMemberRoles,
  createTeamRequestSchema,
  optionalTeamSections,
  rolesData,
  saveRolesRequestSchema,
  sectionOn,
} from "@stall10/shared";
import { describe, expect, it } from "vitest";
import { callerLabel } from "../src/auth.js";
import { listingFor } from "../src/teams/access.js";
import { newTeamDocuments } from "../src/teams/documents.js";

// Written by apps/mobile/test/data/shared_fixtures_test.dart from the app's
// own newTeamDocs, so a team made through the API is the same as one the
// app made itself.
interface Case {
  case: string;
  teamId: string;
  owner: { uid: string; displayName?: string; email?: string };
  request: unknown;
  docs: Record<string, unknown>;
}
const cases: Case[] = JSON.parse(
  readFileSync(new URL("../../../packages/shared/fixtures/team_create.json", import.meta.url), "utf8"),
);

describe("new team documents match the app (fixtures/team_create.json)", () => {
  it.each(cases)("$case", (c) => {
    const input = createTeamRequestSchema.parse(c.request);
    const label = callerLabel({ uid: c.owner.uid, name: c.owner.displayName, email: c.owner.email });
    const docs = newTeamDocuments(c.teamId, input, { uid: c.owner.uid, label }, "<serverTimestamp>");
    expect(docs).toEqual(c.docs);
  });
});

const fixture = (name: string) =>
  JSON.parse(readFileSync(new URL(`../../../packages/shared/fixtures/${name}`, import.meta.url), "utf8"));

describe("a new team starts simple", () => {
  const owner = { uid: "u1", label: "Pat" };
  const docsFor = (request: object) =>
    newTeamDocuments("t1", createTeamRequestSchema.parse(request), owner, "<serverTimestamp>");

  it("a team stores Playbook, Videos, Stats and Meetings off", () => {
    const team = docsFor({ name: "Haze", division: "open", level: "club" })["teams/t1"];
    expect(team.sections).toEqual({ playbook: false, videos: false, stats: false, meetings: false });
    for (const s of optionalTeamSections) expect(sectionOn(team, s)).toBe(false);
  });

  it("the switches stay off the directory listing", () => {
    expect(docsFor({ name: "Haze", division: "open", level: "club" })["teamDirectory/t1"]).not.toHaveProperty("sections");
  });

  it("communities and organizations store none (their defaults are unchanged)", () => {
    for (const kind of ["community", "organization"]) {
      const team = docsFor({ name: "Pickup", division: "mixed", level: "pickup", kind })["teams/t1"];
      expect(team).not.toHaveProperty("sections");
    }
  });

  it("a team with nothing stored (from before) reads every section as on", () => {
    for (const s of optionalTeamSections) {
      expect(sectionOn({}, s)).toBe(true);
      expect(sectionOn({ sections: {} }, s)).toBe(true);
      expect(sectionOn({ sections: { [s]: true } }, s)).toBe(true);
    }
  });
});

describe("a team made in a community matches the app (fixtures/team_community_create.json)", () => {
  it("writes the same documents, naming the community", () => {
    const c = fixture("team_community_create.json") as Case & { org: { id: string; name: string } };
    const input = createTeamRequestSchema.parse(c.request);
    const label = callerLabel({ uid: c.owner.uid, name: c.owner.displayName, email: c.owner.email });
    const docs = newTeamDocuments(c.teamId, input, { uid: c.owner.uid, label }, "<serverTimestamp>", c.org);
    expect(docs).toEqual(c.docs);
  });
});

describe("directory listings match the app (fixtures/team_listing.json)", () => {
  const cases: Array<{ case: string; team: Record<string, unknown>; listing: unknown }> = fixture("team_listing.json");
  it.each(cases)("$case", (c) => {
    expect(listingFor(c.team)).toEqual(c.listing);
  });
});

describe("saved custom roles match the app (fixtures/team_roles.json)", () => {
  const cases: Array<{ case: string; members: string[]; roles: unknown; memberRoles: unknown; saved: unknown }> =
    fixture("team_roles.json");
  it.each(cases)("$case", (c) => {
    const input = saveRolesRequestSchema.parse({ roles: c.roles, memberRoles: c.memberRoles });
    const memberRoles = cleanMemberRoles(input.memberRoles, input.roles, c.members);
    expect(rolesData(input.roles, memberRoles)).toEqual(c.saved);
  });
});
