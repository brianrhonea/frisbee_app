"use client";
import { where } from "firebase/firestore";
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
