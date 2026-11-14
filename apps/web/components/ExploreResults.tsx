"use client";
import type { SearchPage } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { callApi } from "@/lib/client";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { ListingCard } from "./ListingCard";

/** Search results for [q], read with the member's token. */
export function ExploreResults({ q }: { q: string }) {
  const { user } = useAuth();
  const [results, setResults] = useState<{ q: string; page: SearchPage | null } | null>(null);
  useEffect(() => {
    if (!user || !q) return;
    let live = true;
    callApi<SearchPage>(user, `/v1/public/search?q=${encodeURIComponent(q)}`).then(
      (page) => live && setResults({ q, page }),
      () => live && setResults({ q, page: null }),
    );
    return () => {
      live = false;
    };
  }, [user, q]);

  if (!results || results.q !== q) return <p className="muted" aria-busy="true">Searching…</p>;
  const page = results.page;
  if (!page) return <p className="form-error">Couldn&apos;t search. Try again.</p>;
  if (page.players.length === 0 && page.teams.length === 0) {
    return <p className="empty">Nothing matches &ldquo;{q}&rdquo;.</p>;
  }
  return (
    <>
      {page.teams.length > 0 && (
        <>
          <h2 className="section-title">Teams and groups</h2>
          <div className="stack">
            {page.teams.map((t) => (
              <ListingCard key={t.id} team={t} />
            ))}
          </div>
        </>
      )}
      {page.players.length > 0 && (
        <>
          <h2 className="section-title">Players</h2>
          <div className="stack">
            {page.players.map((p) => (
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
  );
}
