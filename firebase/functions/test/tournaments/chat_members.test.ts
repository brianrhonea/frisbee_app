// Who is in a tournament's chats (src/tournaments/chat_members.ts), on the
// same people as apps/api/test/tournament_chats.test.ts.
import { describe, expect, it } from "vitest";
import { captainsOf, entryChatChange, organizersOf } from "../../src/tournaments/chat_members";

const host = { memberIds: ["dir", "vol", "pl1"], members: { dir: "owner", vol: "player", pl1: "player" }, memberPerms: { vol: ["manageEvents"] } };
const haze = { memberIds: ["cap1", "pl1"], members: { cap1: "player", pl1: "player" } };
const bolt = { memberIds: ["adm2"], members: { adm2: "captain" } };

describe("tournament chat members", () => {
  it("organizers have manageEvents on the host", () => {
    expect(organizersOf(host)).toEqual(["dir", "vol"]);
    expect(organizersOf(undefined)).toEqual([]);
  });

  it("captains are the entry's captainIds on the team (with its admins for the team's own thread), while it's in", () => {
    expect(captainsOf({ status: "applied", captainIds: ["cap1", "left"] }, haze)).toEqual(["cap1"]);
    // The Captains' channel: only the roster's captains, not the team's admins.
    expect(captainsOf({ status: "accepted", captainIds: [] }, bolt)).toEqual([]);
    expect(captainsOf({ status: "accepted", captainIds: [] }, bolt, true)).toEqual(["adm2"]);
    expect(captainsOf({ status: "withdrawn", captainIds: ["cap1"] }, haze)).toEqual([]);
    expect(captainsOf({ status: "declined", captainIds: [] }, bolt)).toEqual([]);
    // Invited teams join once they apply.
    expect(captainsOf({ status: "invited", captainIds: ["cap1"] }, haze)).toEqual([]);
  });

  it("only status in or out, and captain changes, matter", () => {
    expect(entryChatChange(undefined, { status: "applied" })).toBe(true);
    expect(entryChatChange({ status: "applied" }, { status: "accepted" })).toBe(false);
    expect(entryChatChange({ status: "accepted" }, { status: "withdrawn" })).toBe(true);
    expect(entryChatChange({ status: "accepted", captainIds: ["a"] }, { status: "accepted", captainIds: ["a", "b"] })).toBe(true);
    expect(entryChatChange({ status: "declined" }, { status: "withdrawn" })).toBe(false);
  });
});
