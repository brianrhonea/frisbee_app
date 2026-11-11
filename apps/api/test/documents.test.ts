import { readFileSync } from "node:fs";
import { createTeamRequestSchema } from "@stall10/shared";
import { describe, expect, it } from "vitest";
import { callerLabel } from "../src/auth.js";
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
