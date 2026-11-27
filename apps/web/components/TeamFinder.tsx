"use client";
import type { PublicListing, SearchPage, TeamSearchPage } from "@stall10/shared";
import { teamSearchMaxLength } from "@stall10/shared";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { getPublicApi, problem } from "@/lib/client";
import { listingSubtitle } from "@/lib/site";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { minQueryLength } from "./explore/filters";
import { ErrorNote } from "@/components/StatusViews";

/** How long typing pauses before searching. */
const pause = 300;

/**
 * Find a team or group by name (`GET /v1/public/teams?q=`), for anyone:
 * visitors (a parent, a friend, a colleague) open a team's public page
 * without joining. The query stays in the address (?q=), so the top bar's
 * search lands here for visitors and a search can be shared. Uses
 * useSearchParams, so render it inside a Suspense boundary.
 */
export function TeamFinder() {
  const { user } = useAuth();
  const [query, setQuery] = useState("");
  const [result, setResult] = useState<{ q: string; teams: PublicListing[] } | null>(null);
  const [error, setError] = useState("");

  // ?q= from the address: on opening, and when the top bar's search sends a new one.
  // What this box last wrote there is skipped, so typing is never overwritten.
  const urlQuery = useSearchParams().get("q") ?? "";
  const written = useRef<string | null>(null);
  useEffect(() => {
    if (urlQuery === written.current) return;
    setQuery(urlQuery);
  }, [urlQuery]);

  const q = query.trim();
  useEffect(() => {
    if (user === undefined || q.length < minQueryLength) return;
    let live = true;
    const timer = setTimeout(() => {
      writeQuery(q);
      setError("");
      // Signed in: the members' search (its teams), which lists every team
      // as the app's search does; visitors get the public finder.
      const page = user
        ? getPublicApi<SearchPage>(user, `/v1/public/search?q=${encodeURIComponent(q)}`)
        : getPublicApi<TeamSearchPage>(user, `/v1/public/teams?q=${encodeURIComponent(q)}`);
      page.then(
        (page) => live && setResult({ q, teams: page.teams }),
        (e) => live && setError(problem(e, "Couldn't search. Try again.")),
      );
    }, pause);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [user, q]);

  /** Keeps the search in the address (?q=) once typing pauses. */
  function writeQuery(value: string) {
    written.current = value;
    const url = new URL(window.location.href);
    if (value) url.searchParams.set("q", value);
    else url.searchParams.delete("q");
    window.history.replaceState(null, "", url);
  }

  function onChange(value: string) {
    setQuery(value);
    if (!value.trim()) writeQuery("");
  }

  const shown = result && result.q === q ? result.teams : null;
  return (
    <section className="card team-finder" id="find" aria-labelledby="find-title">
      <h2 className="card-title" id="find-title">
        Find a team or group
      </h2>
      <p className="muted small">See any team&apos;s page, posts and upcoming events, no account needed.</p>
      <input
        className="search-input"
        type="search"
        placeholder="Search teams, pickup communities, schools and clubs"
        aria-label="Search teams and communities by name"
        maxLength={teamSearchMaxLength}
        value={query}
        onChange={(e) => onChange(e.target.value)}
      />
      {q.length > 0 && q.length < minQueryLength ? (
        <p className="muted small">Type at least {minQueryLength} letters.</p>
      ) : error ? (
        <ErrorNote>{error}</ErrorNote>
      ) : q.length === 0 ? null : !shown ? (
        <p className="muted small" aria-busy="true">
          Searching…
        </p>
      ) : shown.length === 0 ? (
        <p className="muted small">No teams or groups match &ldquo;{q}&rdquo;.</p>
      ) : (
        <div className="stack team-finder-list">
          {shown.map((t) => {
            const group = (t.kind ?? "team") !== "team";
            const sub = listingSubtitle(t);
            return (
              <Link key={t.id} className="row-card" href={`/teams/${encodeURIComponent(t.id)}`}>
                <Avatar name={t.name} />
                <span>
                  <b>{t.name || "Team"}</b>
                  <small>{group ? [sub, t.requiresApproval ? "Approval required" : "Open to join"].filter(Boolean).join(" · ") : sub}</small>
                </span>
              </Link>
            );
          })}
        </div>
      )}
    </section>
  );
}
