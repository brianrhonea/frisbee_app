import { describe, expect, it } from "vitest";

import { inAudience, type VoiceTeam, voiceDecision, voiceRoomName } from "../../src/meetings/model";

const team: VoiceTeam = {
  members: { o: "owner", c: "coach", p1: "player", p2: "player", s: "stats" },
  memberRoles: { p1: ["handlers"] },
};

const lounge = { kind: "voice", readRoles: ["everyone"], writeRoles: ["everyone"] };
const handlers = { kind: "voice", readRoles: ["handlers", "coach"], writeRoles: ["handlers"] };

describe("inAudience", () => {
  it("matches everyone, tiers, custom roles and names", () => {
    expect(inAudience(team, "p2", ["everyone"])).toBe(true);
    expect(inAudience(team, "c", ["coach"])).toBe(true);
    expect(inAudience(team, "s", ["player"])).toBe(true);
    expect(inAudience(team, "p1", ["handlers"])).toBe(true);
    expect(inAudience(team, "p2", ["handlers"])).toBe(false);
    expect(inAudience(team, "p2", [], ["p2"])).toBe(true);
    expect(inAudience(team, "o", [])).toBe(true);
    expect(inAudience(team, "stranger", ["everyone"])).toBe(false);
  });
});

describe("voiceDecision", () => {
  it("lets readers listen and writers talk", () => {
    expect(voiceDecision(team, lounge, "p2")).toEqual({ ok: true, canSpeak: true });
    expect(voiceDecision(team, handlers, "p1")).toEqual({ ok: true, canSpeak: true });
    expect(voiceDecision(team, handlers, "c")).toEqual({ ok: true, canSpeak: false });
  });

  it("turns away outsiders, text rooms and missing channels", () => {
    expect(voiceDecision(team, handlers, "p2")).toMatchObject({ ok: false, code: "permission-denied" });
    expect(voiceDecision(team, lounge, "stranger")).toMatchObject({ ok: false, code: "permission-denied" });
    expect(voiceDecision(undefined, lounge, "p1")).toMatchObject({ ok: false });
    expect(voiceDecision({ ...team, deletingAt: 1 }, lounge, "p1")).toMatchObject({ ok: false });
    expect(voiceDecision(team, undefined, "p1")).toMatchObject({ ok: false, code: "not-found" });
    expect(voiceDecision(team, { ...lounge, kind: "text" }, "p1")).toMatchObject({
      ok: false,
      code: "failed-precondition",
    });
    expect(voiceDecision(team, { readRoles: ["everyone"] }, "p1")).toMatchObject({ ok: false });
  });

  it("names rooms apart from meetings", () => {
    expect(voiceRoomName("t1", "voice-lounge")).toBe("voice:t1:voice-lounge");
  });
});
