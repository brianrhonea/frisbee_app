// A team's chat in the inbox (team_chats.ts) against the app's
// TeamChatSummary (apps/mobile/lib/data/repositories/chat/team_chat_activity.dart),
// on the vectors in fixtures/team_chats (written by
// apps/mobile/test/shared_fixtures/team_chats_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { teamChatSummary } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface SummaryCase {
  name: string;
  rooms: Array<{ id: string; name: string; kind: string; lastAt: string | null; canRead: boolean }>;
  reads: Record<string, string>;
  muted?: string[];
  mentions?: Array<{ roomId: string; text: string; at: string; personal: boolean }>;
  summary: { rooms: string[]; unread: string[]; lastAt: string | null; open: string | null; subtitle: string; mention: string | null };
}

describe("team chats in the inbox match the app (fixtures/team_chats/summary.json)", () => {
  it.each(fixture<SummaryCase>("team_chats/summary.json").cases)("$name", (c) => {
    const s = teamChatSummary(
      c.rooms.filter((r) => r.canRead),
      c.reads,
      (roomId) => (c.muted ?? []).includes(roomId),
      c.mentions ?? [],
    );
    expect({
      rooms: s.rooms.map((r) => r.id),
      unread: s.unread.map((r) => r.id),
      lastAt: s.lastAt,
      open: s.open?.id ?? null,
      subtitle: s.subtitle,
      mention: s.mention?.roomId ?? null,
    }).toEqual(c.summary);
  });
});
