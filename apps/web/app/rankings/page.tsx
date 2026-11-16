import { chooseRanking, rankingWantFromQuery } from "@stall10/shared";
import type { Metadata } from "next";
import { Rankings, type VisitorRankings } from "@/components/Rankings";
import { loadRankings } from "@/lib/rankingsPage";

// Rendered per request (the API answer itself is cached for minutes), so
// an API outage during a build or revalidation can't be baked into the page.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Rankings",
  description:
    "Club, college, league and pickup team rankings from public tournaments on Stall 10, by division, and player ratings from logged stats.",
};

type Search = { kind?: string | string[]; level?: string | string[]; division?: string | string[] };
const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) || undefined;

/**
 * Team rankings, filtered by Level and Division (`?level=club&division=mixed`;
 * the old `?division=club-mixed` still works): server-rendered for visitors
 * and search engines from the public rankings; members get them live. Player
 * ratings (`?kind=players`) are for members.
 */
export default async function RankingsPage({ searchParams }: { searchParams: Promise<Search> }) {
  const q = await searchParams;
  const kind = first(q.kind) === "players" ? "players" : "teams";
  const want = rankingWantFromQuery({ level: first(q.level), division: first(q.division) });
  let visitor: VisitorRankings | null = null;
  if (kind === "teams") {
    const all = await loadRankings();
    if (all) {
      const keys = all.rankings.map((r) => r.key);
      const choice = chooseRanking(keys, want);
      // Only the ranking shown goes in the page.
      visitor = { keys, current: all.rankings.find((r) => r.key === choice?.key) ?? null };
    }
  }
  return (
    <div className="page page-wide">
      <header className="page-head">
        <h1>Rankings</h1>
        <p>Teams from public tournaments, players from logged stats.</p>
      </header>
      <Rankings kind={kind} want={want} visitor={visitor} />
    </div>
  );
}
