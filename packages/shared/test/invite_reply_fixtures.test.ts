// Invites' reply-by time and expiry (inviteReplyBy, inviteExpired in
// tournaments.ts) against the app's HostedTournament.inviteReplyBy and
// TournamentEntry.isExpired, on fixtures/invite_reply (written by
// apps/mobile/test/shared_fixtures/invite_reply_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { inviteExpired, inviteReplyBy, inviteReplyChoices, inviteReplyLabel, defaultInviteReplyDays } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

type Case =
  | { startsOn: string; days: number | null; now: string; replyBy: string | null }
  | { status: string; replyBy: string | null; now: string; expired: boolean }
  | { choices: number[]; defaultDays: number; labels: string[] };

describe("invite reply-by matches the app (fixtures/invite_reply/cases.json)", () => {
  const cases = fixture<Case>("invite_reply/cases.json").cases;
  it("works out the same reply-by time", () => {
    for (const c of cases) {
      if (!("days" in c)) continue;
      const by = inviteReplyBy(new Date(c.startsOn), c.days, new Date(c.now));
      expect(by?.toISOString() ?? null).toBe(c.replyBy);
    }
  });
  it("expires the same invites", () => {
    for (const c of cases) if ("expired" in c) expect(inviteExpired(c, new Date(c.now))).toBe(c.expired);
  });
  it("offers the same choices", () => {
    for (const c of cases) {
      if (!("choices" in c)) continue;
      expect([...inviteReplyChoices]).toEqual(c.choices);
      expect(defaultInviteReplyDays).toBe(c.defaultDays);
      expect([null, ...inviteReplyChoices].map(inviteReplyLabel)).toEqual(c.labels);
    }
  });
});
