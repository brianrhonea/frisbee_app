"use client";
// The Chats tab's bubble (ShellViewModel.unreadMessages in the app):
// conversations and team chats with a message the member hasn't read,
// leaving out the ones they've muted. Muting hides the bubble as well as
// the notifications.
import { mutedConversationKey } from "@stall10/shared";
import { limit, where } from "firebase/firestore";
import { useMemo } from "react";
import { useLiveDoc, useLiveQuery } from "@/lib/live";
import { type Conversation, describe, type Mine } from "./conversations";
import { useTeamChats } from "./useTeamChats";

/** The member's muted rooms and conversations (users/{uid}/settings/notifications.mutedRooms). */
export function useMutedRooms(uid: string | null | undefined): Set<string> {
  const prefs = useLiveDoc<{ mutedRooms?: string[] }>(uid ? `users/${uid}/settings/notifications` : null);
  const list = prefs.data?.mutedRooms;
  return useMemo(() => new Set(list ?? []), [list]);
}

/** Unread, unmuted conversations plus team chats with an unread, unmuted room. */
export function useUnreadChats(uid: string | null | undefined): number {
  const convs = useLiveQuery<Conversation>(uid ? "conversations" : null, [where("participants", "array-contains", uid ?? ""), limit(200)], `chats-${uid ?? ""}`);
  const reads = useLiveQuery<Mine>(uid ? `users/${uid}/dmReads` : null, [limit(400)], `dmreads-${uid ?? ""}`);
  const muted = useMutedRooms(uid);
  const team = useTeamChats(uid);
  return useMemo(() => {
    if (!uid) return 0;
    const mine = new Map((reads.data ?? []).map((r) => [r.id, r] as const));
    const direct = (convs.data ?? []).filter((c) => {
      const d = describe(c, mine.get(c.id), uid);
      return d.unread && d.inInbox && !muted.has(mutedConversationKey(c.id));
    }).length;
    return direct + team.unread;
  }, [uid, convs.data, reads.data, muted, team.unread]);
}
