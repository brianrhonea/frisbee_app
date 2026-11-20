"use client";
import { orderBy, where } from "firebase/firestore";
import { useLiveQuery } from "@/lib/live";
import type { TeamDoc } from "./team/TeamContext";

/**
 * The teams and groups [uid] is on, live (watchMyTeams; the rules let
 * members read their teams). One query shape everywhere, so the pages and
 * columns that list them share a single listener.
 */
export function useMyTeams<T = TeamDoc>(uid: string | null | undefined) {
  return useLiveQuery<T>(uid ? "teams" : null, uid ? [where("memberIds", "array-contains", uid)] : [], uid ?? "");
}

/**
 * The member's only team or community, when they're on exactly one and
 * have no invitation waiting (the app's TeamsViewModel.single): the Teams
 * tab then opens its hub straight away. Null otherwise, and while loading.
 */
export function useSingleTeam(uid: string | null | undefined): string | null {
  const teams = useMyTeams<{ name?: string }>(uid);
  // The same query as TeamInvites, so Firestore shares one listener.
  const invites = useLiveQuery(uid ? `users/${uid}/teamInvites` : null, [orderBy("createdAt", "desc")], uid ?? "");
  if (!uid || teams.error || !teams.data || teams.data.length !== 1) return null;
  if (!invites.data || invites.data.length > 0) return null;
  return teams.data[0]!.id;
}
