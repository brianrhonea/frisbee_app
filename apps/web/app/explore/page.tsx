import type { Metadata } from "next";
import { Explore } from "@/components/explore/Explore";
import { type ExploreFilter, exploreFilters } from "@/components/explore/filters";
import { ForVisitors } from "@/components/ForVisitors";
import { MembersOnly } from "@/components/MembersOnly";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Explore",
  description: "Search for ultimate players, teams, communities and tournaments on Stall 10.",
};

type Props = { searchParams: Promise<{ q?: string | string[]; only?: string | string[] }> };

const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);

/** Members only: search runs in the browser with their token. */
export default async function ExplorePage({ searchParams }: Props) {
  const params = await searchParams;
  const q = first(params.q)?.trim().slice(0, 100) ?? "";
  const raw = first(params.only);
  const only = exploreFilters.includes(raw as ExploreFilter) ? (raw as ExploreFilter) : null;
  const query = new URLSearchParams({ ...(q && { q }), ...(only && { only }) }).toString();
  const next = query ? `/explore?${query}` : "/explore";
  return (
    <div className="page">
      <div className="page-head">
        <h1>Explore</h1>
        <p>Find your next point. Players, teams, communities and tournaments.</p>
      </div>
      <MembersOnly next={next} what="Sign up free or log in to search for players, teams, communities and tournaments.">
        <Explore initialQuery={q} initialFilter={only} />
      </MembersOnly>
      <ForVisitors>
        <p className="muted">
          No account needed for the <Link href="/rankings">team rankings</Link> or{" "}
          <Link href="/tournaments">tournaments and leagues</Link>.
        </p>
      </ForVisitors>
    </div>
  );
}
