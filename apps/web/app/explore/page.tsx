import type { Metadata } from "next";
import Link from "next/link";
import { ExploreResults } from "@/components/ExploreResults";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = {
  title: "Explore",
  description: "Search for ultimate players, teams and pickup groups on Stall 10.",
};

type Props = { searchParams: Promise<{ q?: string | string[] }> };

/** Members only: search runs in the browser with their token. */
export default async function Explore({ searchParams }: Props) {
  const raw = (await searchParams).q;
  const q = (Array.isArray(raw) ? raw[0] : raw)?.trim().slice(0, 100) ?? "";
  const next = q ? `/explore?q=${encodeURIComponent(q)}` : "/explore";
  return (
    <div className="page">
      <div className="page-head">
        <h1>Explore</h1>
        <p>Find players, teams and pickup groups.</p>
      </div>
      <MembersOnly next={next} what="Sign up free or log in to search for players, teams and pickup groups.">
        <form className="search-form" action="/explore" method="get" role="search">
          <label className="visually-hidden" htmlFor="q">
            Search Stall 10
          </label>
          <input id="q" name="q" type="search" defaultValue={q} placeholder="Search players and teams" autoComplete="off" />
          <button className="btn btn-primary" type="submit">
            Search
          </button>
        </form>
        {q ? (
          <ExploreResults q={q} />
        ) : (
          <>
            <h2 className="section-title">Browse</h2>
            <div className="stack">
              <Link className="row-card" href="/rankings">
                <span>
                  <b>Team rankings</b>
                  <small>Teams by division, from public tournaments</small>
                </span>
              </Link>
              <Link className="row-card" href="/rankings?kind=players">
                <span>
                  <b>Player ratings</b>
                  <small>From stats logged with the game tracker</small>
                </span>
              </Link>
            </div>
          </>
        )}
      </MembersOnly>
    </div>
  );
}
