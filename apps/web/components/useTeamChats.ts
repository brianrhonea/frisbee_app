"use client";
import { type InboxRoom, mutedRoomKey, teamChatSummary, type TeamChatSummary } from "@stall10/shared";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { useEffect, useMemo, useState } from "react";
import { firestoreDb } from "@/lib/firebase";
import { type Doc, plain, useLiveQuery } from "@/lib/live";
import type { ManagedRoom } from "./team/ChatManager";
import { memberViewer, type TeamDoc } from "./team/TeamContext";
import { useMyTeams } from "./useMyTeams";
import { useMutedRooms } from "./useUnreadChats";

export type ChatRoomDoc = Doc<ManagedRoom & InboxRoom>;

/** A team's chat in the inbox (TeamChatActivity in the app). */
export interface TeamChat extends TeamChatSummary<ChatRoomDoc> {
  team: Doc<TeamDoc>;
}

/** Whether [uid] can read [room] on [team] (canReadRoom in the rules). */
export function canReadRoom(team: Doc<TeamDoc>, uid: string, room: ManagedRoom): boolean {
  const viewer = memberViewer(team, uid);
  return viewer.tier === "owner" || viewer.audience.some((a) => room.readRoles?.includes(a)) || (room.readUsers ?? []).includes(uid);
}

/**
 * Every team and community chat of [uid]'s, live: the rooms they can read
 * (asked once per audience id, as the rules require, like TeamChat) and
 * which have messages they haven't read (lastAt against their private
 * users/{uid}/chatReads). Unread first, then newest, then by name.
 */
export function useTeamChats(uid: string | null | undefined): { chats: TeamChat[] | undefined; unread: number } {
  const teams = useMyTeams(uid);
  const reads = useLiveQuery<{ rooms?: Record<string, string> }>(uid ? `users/${uid}/chatReads` : null, [], uid ?? "");
  const [rooms, setRooms] = useState<Record<string, ChatRoomDoc[]>>({});
  const muted = useMutedRooms(uid);

  // Re-ask when the teams, or the member's roles on them, change.
  const key = (teams.data ?? [])
    .map((t) => {
      const v = memberViewer(t, uid ?? "");
      return `${t.id}:${v.can("manageChats") ? "*" : v.audience.join(",")}`;
    })
    .join("|");
  useEffect(() => {
    const db = firestoreDb();
    if (!uid || !db || !teams.data) return;
    const stops: Array<() => void> = [];
    for (const t of teams.data) {
      const v = memberViewer(t, uid);
      const queries = v.can("manageChats")
        ? [[]]
        : [...v.audience.map((id) => [where("readRoles", "array-contains", id)]), [where("readUsers", "array-contains", uid)]];
      const results: Array<ChatRoomDoc[] | undefined> = queries.map(() => undefined);
      queries.forEach((constraints, i) =>
        stops.push(
          onSnapshot(
            query(collection(db, `teams/${t.id}/chats`), ...constraints),
            (snap) => {
              results[i] = snap.docs.map((d) => ({ ...(plain(d.data()) as ManagedRoom & InboxRoom), id: d.id }));
              if (results.some((r) => r === undefined)) return;
              const byId = new Map<string, ChatRoomDoc>();
              for (const r of results) for (const d of r!) byId.set(d.id, d);
              setRooms((prev) => ({ ...prev, [t.id]: [...byId.values()] }));
            },
            () => setRooms((prev) => ({ ...prev, [t.id]: [] })),
          ),
        ),
      );
    }
    return () => stops.forEach((stop) => stop());
    // eslint-disable-next-line react-hooks/exhaustive-deps -- [key] stands for the teams and roles.
  }, [uid, key]);

  const chats = useMemo(() => {
    if (!uid || !teams.data) return undefined;
    const readsByTeam = new Map((reads.data ?? []).map((r) => [r.id, r.rooms ?? {}] as const));
    const byPosition = (a: ChatRoomDoc, b: ChatRoomDoc) => (a.position ?? 0) - (b.position ?? 0) || (a.name ?? "").localeCompare(b.name ?? "");
    const out: TeamChat[] = teams.data.map((team) => ({
      team,
      ...teamChatSummary(
        (rooms[team.id] ?? []).filter((r) => canReadRoom(team, uid, r)).sort(byPosition),
        readsByTeam.get(team.id) ?? {},
        (roomId) => muted.has(mutedRoomKey(team.id, roomId)),
      ),
    }));
    const at = (iso: string | null) => (iso ? Date.parse(iso) : 0);
    return out.sort(
      (a, b) =>
        Number(b.unread.length > 0) - Number(a.unread.length > 0) ||
        at(b.lastAt) - at(a.lastAt) ||
        (a.team.name ?? "").toLowerCase().localeCompare((b.team.name ?? "").toLowerCase()),
    );
  }, [uid, teams.data, reads.data, rooms, muted]);

  return { chats, unread: chats?.filter((c) => c.unread.length > 0).length ?? 0 };
}
