"use client";
import { searchKeywords } from "@stall10/shared";
import { useAuth } from "../AuthProvider";
import { useLiveDoc } from "@/lib/live";

/** The parts of profiles/{uid} (and private/details) settings edit. */
export interface MyProfile {
  name?: string;
  username?: string;
  photoUrl?: string | null;
  private?: boolean;
  bio?: string;
  pronouns?: string;
  hometown?: string;
  school?: string;
  throwingHand?: "right" | "left" | "both" | null;
  playingSince?: number | null;
  visibility?: { stats?: boolean; teams?: boolean; games?: boolean };
  teams?: Array<{ name?: string }>;
}

/**
 * The signed-in member's own profile, live: its public document merged
 * with private/details while it's private (where the details live then).
 */
export function useMyProfile(): { profile: MyProfile | undefined; error: string | null } {
  const { user } = useAuth();
  const base = useLiveDoc<MyProfile>(user ? `profiles/${user.uid}` : null);
  const hidden = useLiveDoc<MyProfile>(user && base.data?.private ? `profiles/${user.uid}/private/details` : null);
  const error = base.error ?? hidden.error;
  if (base.data === undefined) return { profile: undefined, error };
  if (base.data?.private && hidden.data === undefined) return { profile: undefined, error };
  return { profile: { ...(base.data ?? {}), ...(hidden.data ?? {}) }, error };
}

/** Search tags as the app works them out (PlayerProfile.searchTags): school, hometown, teams. */
export function searchTagsFor(p: MyProfile): string[] {
  return searchKeywords([p.school ?? "", p.hometown ?? "", ...(p.teams ?? []).map((t) => t.name ?? "")].join(" "));
}
