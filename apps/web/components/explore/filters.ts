// Discover's filters and matching, shared by the page (server) and the
// search card (browser).
import { hostedType, type PublicListing, type TournamentDoc } from "@stall10/shared";

/**
 * The chips under the search box, by their `?only=` names (the app's
 * ExploreFilter, so links work on both); null is All. `groups` is shown
 * as Communities; `players` (People) is members only, as visitors can't
 * search players.
 */
export type ExploreFilter = "tournaments" | "leagues" | "pickup" | "teams" | "groups" | "players";
export const exploreFilters: ExploreFilter[] = ["tournaments", "leagues", "pickup", "teams", "groups", "players"];

/** Other names the chips answer to in a link. */
const aliases: Record<string, ExploreFilter> = { communities: "groups", people: "players" };

/** The filter a `?only=` value names, or null (All) for none or an unknown one. */
export function parseFilter(raw: string | null | undefined): ExploreFilter | null {
  if (!raw) return null;
  if (exploreFilters.includes(raw as ExploreFilter)) return raw as ExploreFilter;
  return aliases[raw] ?? null;
}

/** Letters a search needs (TeamSearchViewModel.minQueryLength). */
export const minQueryLength = 2;

const words = (query: string) => query.toLowerCase().split(/\s+/).filter(Boolean);

/** Upcoming tournaments whose name, host or place has every word of [query] (ExploreViewModel.matching). */
export function matchTournaments<T extends Pick<TournamentDoc, "name" | "hostName" | "location">>(list: T[], query: string): T[] {
  const w = words(query);
  if (w.length === 0) return [];
  return list.filter((t) => {
    const text = `${t.name ?? ""} ${t.hostName ?? ""} ${t.location ?? ""}`.toLowerCase();
    return w.every((x) => text.includes(x));
  });
}

/** Items whose [text] has every word of [query]; none for an empty query. */
export function matchText<T>(list: T[], query: string, text: (item: T) => string): T[] {
  const w = words(query);
  if (w.length === 0) return [];
  return list.filter((item) => {
    const t = text(item).toLowerCase();
    return w.every((x) => t.includes(x));
  });
}

type Hosted = Pick<TournamentDoc, "kind" | "entryType" | "teamEntry">;

/** Hosted events a chip shows: leagues for Leagues, tournaments and hat tournaments for Tournaments. */
export function hostedFor<T extends Hosted>(list: T[], only: ExploreFilter | null): T[] {
  if (only === null) return list;
  if (only === "leagues") return list.filter((t) => hostedType(t) === "league");
  if (only === "tournaments") return list.filter((t) => hostedType(t) !== "league");
  return [];
}

/**
 * Teams and groups a chip shows: Teams the teams; Communities pickup
 * communities and schools or clubs; Pickup only pickup communities.
 */
export function listingsFor(teams: PublicListing[], only: ExploreFilter | null): PublicListing[] {
  if (only === "teams") return teams.filter((t) => (t.kind ?? "team") === "team");
  if (only === "groups") return teams.filter((t) => (t.kind ?? "team") !== "team");
  if (only === "pickup") return teams.filter((t) => t.kind === "community");
  if (only === null) return teams;
  return [];
}

/** Public team events a chip shows: every one for All, pickup games for Pickup. */
export function eventsFor<T extends { type?: string }>(events: T[], only: ExploreFilter | null): T[] {
  if (only === null) return events;
  if (only === "pickup") return events.filter((e) => e.type === "pickup");
  return [];
}

/** /explore (Discover) with the search and filter, as the app's Routes.explore. */
export function exploreHref(q: string, only: ExploreFilter | null): string {
  const p = new URLSearchParams();
  if (q.trim()) p.set("q", q.trim());
  if (only) p.set("only", only);
  const s = p.toString();
  return s ? `/explore?${s}` : "/explore";
}
