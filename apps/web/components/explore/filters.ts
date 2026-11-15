// Explore's filters and matching, shared by the page (server) and the
// search card (browser).
import type { PublicListing, TournamentDoc } from "@stall10/shared";

/** The chips under the search box (ExploreFilter); null is All. */
export type ExploreFilter = "players" | "teams" | "groups" | "tournaments";
export const exploreFilters: ExploreFilter[] = ["players", "teams", "groups", "tournaments"];

/** Letters a search needs (TeamSearchViewModel.minQueryLength). */
export const minQueryLength = 2;

/** Upcoming tournaments whose name, host or place has every word of [query] (ExploreViewModel.matching). */
export function matchTournaments<T extends Pick<TournamentDoc, "name" | "hostName" | "location">>(list: T[], query: string): T[] {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return [];
  return list.filter((t) => {
    const text = `${t.name ?? ""} ${t.hostName ?? ""} ${t.location ?? ""}`.toLowerCase();
    return words.every((w) => text.includes(w));
  });
}

/** Teams, groups (communities and schools or clubs) or both (TeamSearchViewModel.results). */
export function listingsFor(teams: PublicListing[], only: ExploreFilter | null): PublicListing[] {
  if (only === "teams") return teams.filter((t) => (t.kind ?? "team") === "team");
  if (only === "groups") return teams.filter((t) => (t.kind ?? "team") !== "team");
  return teams;
}

/** /explore with the search and filter, as the app's Routes.explore. */
export function exploreHref(q: string, only: ExploreFilter | null): string {
  const p = new URLSearchParams();
  if (q.trim()) p.set("q", q.trim());
  if (only) p.set("only", only);
  const s = p.toString();
  return s ? `/explore?${s}` : "/explore";
}
