import type { SearchPage } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import { Avatar } from "@/components/Avatar";
import { ListingCard } from "@/components/ListingCard";
import { getPublic } from "@/lib/api";

export const metadata: Metadata = {
  title: "Explore",
  description: "Search for ultimate players, teams and pickup groups on Stall 10.",
};

type Props = { searchParams: Promise<{ q?: string | string[] }> };

export default async function Explore({ searchParams }: Props) {
  const raw = (await searchParams).q;
  const q = (Array.isArray(raw) ? raw[0] : raw)?.trim().slice(0, 100) ?? "";
  const results = q ? await getPublic<SearchPage>("/v1/public/search", { q }) : null;
  return (
    <div className="page">
      <div className="page-head">
        <h1>Explore</h1>
        <p>Find players, teams and pickup groups.</p>
      </div>
      <form className="search-form" action="/explore" method="get" role="search">
        <label className="visually-hidden" htmlFor="q">
          Search Stall 10
        </label>
        <input id="q" name="q" type="search" defaultValue={q} placeholder="Search players and teams" autoComplete="off" />
        <button className="btn btn-primary" type="submit">
          Search
        </button>
      </form>
      {results &&
        (results.players.length === 0 && results.teams.length === 0 ? (
          <p className="empty">Nothing matches &ldquo;{q}&rdquo;.</p>
        ) : (
          <>
            {results.teams.length > 0 && (
              <>
                <h2 className="section-title">Teams and groups</h2>
                <div className="stack">
                  {results.teams.map((t) => (
                    <ListingCard key={t.id} team={t} />
                  ))}
                </div>
              </>
            )}
            {results.players.length > 0 && (
              <>
                <h2 className="section-title">Players</h2>
                <div className="stack">
                  {results.players.map((p) => (
                    <Link key={p.id} className="row-card" href={`/players/${encodeURIComponent(p.id)}`}>
                      <Avatar name={p.name} url={p.photoUrl} />
                      <span>
                        <b>{p.name || "Player"}</b>
                        {p.username && <small>@{p.username}</small>}
                      </span>
                    </Link>
                  ))}
                </div>
              </>
            )}
          </>
        ))}
    </div>
  );
}
