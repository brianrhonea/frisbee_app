"use client";
import { clubTooYoungMessage, isClubTeam } from "@stall10/shared";
import { useLiveDoc } from "@/lib/live";

/** teamDirectory/{teamId}: what the age rule needs from a team's listing. */
interface Listing {
  kind?: string;
  level?: string;
}

/**
 * Whether [teamId] is a club team (16 and over), from its public listing;
 * false until it loads, or when it isn't listed. The API checks ages when
 * someone joins; this only explains the rule up front.
 */
export function useIsClubTeam(teamId: string | null): boolean {
  const listing = useLiveDoc<Listing>(teamId ? `teamDirectory/${teamId}` : null);
  return !!listing.data && isClubTeam(listing.data);
}

/** "Club teams are for players 16 and over", with an optional follow-on. */
export function ClubAgeNote({ more }: { more?: string }) {
  return <p className="muted small">{more ? `${clubTooYoungMessage} ${more}` : clubTooYoungMessage}</p>;
}
