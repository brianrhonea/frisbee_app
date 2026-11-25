// A hosted tournament's chats with its organizers (tournament_chats.ts in
// packages/shared). Each is a conversation of kind "tournament": the
// conversations rules let its participants read and post but not add,
// remove or rename (groupDoc() is false), and only the server creates them
// (the client group create rule needs kind "group"). Which conversation
// belongs to which chat is in the server-only pointer
// tournaments/{t}/chats/{captains | team_<teamId>}, so an id can't be
// claimed first. Who is in each is worked out from the tournament on each
// open: the host's organizers (manageEvents) and the captains of entries
// that applied and are still in (captainIds and the team's admins). The tournaments-chatMembers
// function does the same when an entry changes (chat_members.ts there).
import {
  captainsChatName,
  teamChatName,
  tournamentChatSizeMax,
  tournamentChatStatuses,
  type TournamentChatKind,
  type TournamentChatResult,
} from "@stall10/shared";
import type { Caller } from "../auth.js";
import { ApiError } from "../errors.js";
import { docIdParam } from "../ids.js";
import { type Data, type DocStore, serverTime } from "../store.js";
import { can, clip, mapOf, strings } from "../teams/access.js";

const p = {
  tournament: (t: string) => `tournaments/${t}`,
  entries: (t: string) => `tournaments/${t}/entries`,
  entry: (t: string, team: string) => `tournaments/${t}/entries/${team}`,
  pointer: (t: string, chat: string) => `tournaments/${t}/chats/${chat}`,
  team: (id: string) => `teams/${id}`,
  profile: (uid: string) => `profiles/${uid}`,
  conv: (id: string) => `conversations/${id}`,
};

/** Entries read for the Captains' channel: more than any tournament takes. */
export const chatEntriesMax = 500;

const active = (entry: Data | null | undefined) =>
  !!entry && (tournamentChatStatuses as readonly string[]).includes(String(entry.status ?? ""));

/** The host's organizers: who has manageEvents on the hosting team (manages() in the rules). */
export const organizersOf = (host: Data | null): string[] =>
  host ? strings(host.memberIds).filter((u) => can(host, u, "manageEvents")) : [];

/**
 * An entry's captains, still on the team: its captainIds (picked with the
 * roster). The Captains' channel has only those; a team's own thread with
 * the organizers also has the team's admins (teamAdmin()) ([withAdmins]).
 */
export function captainsOf(entry: Data | null | undefined, team: Data | null, withAdmins = false): string[] {
  if (!entry || !active(entry) || !team) return [];
  const members = strings(team.memberIds);
  const admins = withAdmins ? members.filter((u) => can(team, u, "manageTeam")) : [];
  return [...new Set([...strings(entry.captainIds).filter((u) => members.includes(u)), ...admins])];
}

const cap = (uids: string[]) => [...new Set(uids)].slice(0, tournamentChatSizeMax);

/** Who belongs in a chat now, and its name. */
export interface ChatMembers {
  participants: string[];
  name: string;
}

export class TournamentChatService {
  constructor(private readonly store: DocStore) {}

  /** `POST /v1/tournaments/:id/chats/captains`: organizers and entered teams' captains. */
  async captains(caller: Caller, rawId: unknown): Promise<TournamentChatResult> {
    const id = docIdParam(rawId);
    const members = await this.members(id, "captains");
    if (!members?.participants.includes(caller.uid)) {
      throw new ApiError("permission_denied", "Only the organizers and the captains of teams in this tournament are in its Captains' channel.");
    }
    return { id: await this.save(id, "captains", members) };
  }

  /** `POST /v1/tournaments/:id/chats/teams/:teamId`: a team's captains and the organizers. */
  async team(caller: Caller, rawId: unknown, rawTeam: unknown): Promise<TournamentChatResult> {
    const id = docIdParam(rawId);
    const teamId = docIdParam(rawTeam);
    const members = await this.members(id, "team", teamId);
    if (!members?.hasEntry || !members.participants.includes(caller.uid)) {
      throw new ApiError("permission_denied", "Only the organizers and this team's captains can message about its entry.");
    }
    return { id: await this.save(id, "team", members, teamId) };
  }

  /**
   * Who belongs in a chat now, or null when the tournament is gone or still
   * a draft (its chats wait until it's out). For a team's thread,
   * [hasEntry] says whether the team is still in it.
   */
  async members(tournamentId: string, kind: TournamentChatKind, teamId?: string): Promise<(ChatMembers & { hasEntry: boolean }) | null> {
    const t = await this.store.get(p.tournament(tournamentId));
    if (!t || (t.status ?? "draft") === "draft") return null;
    const host = await this.store.get(p.team(String(t.hostId ?? "")));
    const organizers = organizersOf(host);
    const name = String(t.name ?? "");
    if (kind === "team") {
      const [entry, team] = await this.store.getAll([p.entry(tournamentId, teamId!), p.team(teamId!)]);
      const teamName = String(entry?.teamName ?? team?.name ?? "");
      return {
        participants: cap([...organizers, ...captainsOf(entry, team, true)]),
        name: teamChatName(teamName, name),
        hasEntry: active(entry),
      };
    }
    const entries = (await this.store.list(p.entries(tournamentId), chatEntriesMax)).filter((e) => active(e.data));
    const teams = await this.store.getAll(entries.map((e) => p.team(e.id)));
    const captains = entries.flatMap((e, i) => captainsOf(e.data, teams[i]));
    return { participants: cap([...organizers, ...captains]), name: captainsChatName(name), hasEntry: true };
  }

  /**
   * Creates the chat, or brings its people and name up to date keeping
   * everyone's read times and names; returns the conversation id.
   */
  async save(tournamentId: string, kind: TournamentChatKind, m: ChatMembers, teamId?: string): Promise<string> {
    const chat = kind === "captains" ? "captains" : `team_${teamId}`;
    const pointerPath = p.pointer(tournamentId, chat);
    // Names from what's there now; the transaction below settles which
    // conversation it is, so two first opens at once share one.
    const before = await this.store.get(pointerPath);
    const existing = typeof before?.conversationId === "string" ? await this.store.get(p.conv(before.conversationId)) : null;
    const known = mapOf(existing?.names);
    const fresh = `g-${this.store.newId("conversations").replace(/[^A-Za-z0-9]/g, "") || "x"}`;
    const missing = m.participants.filter((u) => typeof known[u] !== "string");
    const profiles = await this.store.getAll(missing.map((u) => p.profile(u)));
    const names: Record<string, unknown> = {};
    for (const u of m.participants) {
      if (typeof known[u] === "string") {
        names[u] = known[u];
        continue;
      }
      const prof = profiles[missing.indexOf(u)];
      names[u] = clip(typeof prof?.name === "string" && prof.name ? prof.name : "Player", 80);
    }
    return this.store.transact(async (tx) => {
      const pointer = await tx.get(pointerPath);
      const id = typeof pointer?.conversationId === "string" ? pointer.conversationId : fresh;
      const now = await tx.get(p.conv(id));
      if (now) {
        // Keep the names it has for people already in it.
        const had = mapOf(now.names);
        const merged = Object.fromEntries(m.participants.map((u) => [u, typeof had[u] === "string" ? had[u] : names[u]]));
        tx.update(p.conv(id), { participants: m.participants, names: merged, name: m.name });
        return id;
      }
      tx.create(p.conv(id), {
        kind: "tournament",
        tournamentId,
        tournamentChat: kind,
        ...(teamId && { teamId }),
        name: m.name,
        createdBy: "",
        participants: m.participants,
        names,
        lastMessage: "",
        lastMessageAt: null,
        lastSenderId: "",
        readAt: {},
        createdAt: serverTime,
      });
      tx.set(pointerPath, { conversationId: id, kind, ...(teamId && { teamId }), createdAt: serverTime });
      return id;
    });
  }
}
