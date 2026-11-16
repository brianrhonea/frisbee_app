import { type PublicHostedList, type PublicHostedPage, type PublicTeamPost, type TeamPage, tournamentFollowKey } from "@stall10/shared";
import { cache } from "react";
import { getPublicOrNull } from "./api";

/**
 * Upcoming published tournaments and leagues (`/v1/public/tournaments`),
 * or null when the API can't answer, so members still get their live list.
 */
export const loadTournaments = cache(async (): Promise<PublicHostedList | null> => {
  try {
    return await getPublicOrNull<PublicHostedList>("/v1/public/tournaments");
  } catch {
    return null;
  }
});

/**
 * An event's public page with [division]'s games (`/v1/public/tournaments/:id`),
 * once per request for the metadata and the page. Null for a draft, a
 * private group's event, a missing one or an API failure: the members'
 * live page then decides (its host can still open a draft).
 */
export const loadTournament = cache(async (id: string, division?: string): Promise<PublicHostedPage | null> => {
  try {
    return await getPublicOrNull<PublicHostedPage>(`/v1/public/tournaments/${encodeURIComponent(id)}`, { division });
  } catch {
    return null;
  }
});

/** The host's public posts tagged with the event (its News tab), from the host's public page. */
export const loadTournamentNews = cache(async (hostId: string, tournamentId: string): Promise<PublicTeamPost[]> => {
  if (!hostId) return [];
  try {
    const team = await getPublicOrNull<TeamPage>(`/v1/public/teams/${encodeURIComponent(hostId)}`);
    const key = tournamentFollowKey(hostId, tournamentId);
    return (team?.posts ?? []).filter((p) => p.tournamentKey === key);
  } catch {
    return [];
  }
});
