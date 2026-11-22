// "At a tournament" tags (follows.ts) against the app's parseTournamentKey
// and tournamentTagOpen (apps/mobile/lib/domain/models/follow.dart), on the
// vectors in fixtures/tournament_tags (written by
// apps/mobile/test/shared_fixtures/tournament_tag_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { parseTournamentKey, tournamentTagHref, tournamentTagOpen } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface TagCase {
  name: string;
  startsOn?: string;
  endsOn?: string | null;
  now?: string;
  open?: boolean;
  key?: string;
  parsed?: { hostId: string; tournamentId: string } | null;
}

describe("tournament tags match the app (fixtures/tournament_tags/cases.json)", () => {
  it.each(fixture<TagCase>("tournament_tags/cases.json").cases)("$name", (c) => {
    if (c.key !== undefined) expect(parseTournamentKey(c.key)).toEqual(c.parsed);
    else expect(tournamentTagOpen(c.startsOn!, c.endsOn, new Date(c.now!))).toBe(c.open);
  });

  it("links open the hosted page, which falls back to the group's", () => {
    expect(tournamentTagHref("tournament_host1_t1")).toBe("/tournaments/t1?host=host1");
    expect(tournamentTagHref("team_x")).toBeNull();
  });
});
