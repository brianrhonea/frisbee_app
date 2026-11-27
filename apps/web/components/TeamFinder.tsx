"use client";
import type { PublicListing, SearchPage, TeamSearchPage } from "@stall10/shared";
import { teamSearchMaxLength } from "@stall10/shared";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { callApi, getPublicApi, problem } from "@/lib/client";
import { listingSubtitle } from "@/lib/site";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { ListRow } from "./ui/ListRow";
import { Button } from "./ui/Button";
import { useMyTeams } from "./useMyTeams";
import "./team_finder.css";
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
  // Teams already joined, so they get no Join button.
  const mine = useMyTeams<{ id: string }>(user?.uid);
  const mineIds = new Set((mine.data ?? []).map((t) => t.id));

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
    <section className="teams-section team-finder" id="find" aria-labelledby="find-title">
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
        <ul className="teams-rows team-finder-list">
          {shown.map((t) => {
            const group = (t.kind ?? "team") !== "team";
            const sub = listingSubtitle(t);
            return (
              <li key={t.id}>
                <ListRow
                  href={`/teams/${encodeURIComponent(t.id)}`}
                  leading={<Avatar name={t.name} size={40} />}
                  title={t.name || "Team"}
                  subtitle={group ? [sub, t.requiresApproval ? "Approval required" : "Open to join"].filter(Boolean).join(" · ") : sub}
                  trailing={
                    user && mine.data !== undefined ? (
                      mineIds.has(t.id) ? (
                        <span className="muted small">Member</span>
                      ) : (
                        <FinderJoin team={t} />
                      )
                    ) : undefined
                  }
                />
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

/** What Join does for a listing, by the same rules as the team header's JoinButton, or null when there is no join path. */
export function joinPathOf(t: Pick<PublicListing, "kind" | "requiresApproval" | "allowJoinRequests">): { label: string; path: string; done: string } | null {
  if ((t.kind ?? "team") === "team") {
    // A team joins by code or invite unless it takes join requests.
    return t.allowJoinRequests === true ? { label: "Ask to join", path: "join-requests", done: "Requested" } : null;
  }
  return t.requiresApproval === true
    ? { label: "Ask to join", path: "join-requests", done: "Requested" }
    : { label: "Join", path: "members", done: "Joined" };
}

/**
 * Join on a search result, only where a join path exists (an open group joins, an approval group or a team
 * that takes requests asks). The API decides, including a club team's 16+ rule: its message is shown.
 */
export function FinderJoin({ team }: { team: PublicListing }) {
  const { user } = useAuth();
  const [state, setState] = useState<"idle" | "busy" | "done">("idle");
  const [error, setError] = useState("");
  const join = joinPathOf(team);
  if (!user || !join) return null;
  async function run() {
    if (!user || !join) return;
    setState("busy");
    setError("");
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(team.id)}/${join.path}`, { method: "POST" });
      setState("done");
    } catch (e) {
      setError(problem(e, "Couldn't do that. Try again."));
      setState("idle");
    }
  }
  return (
    <span className="finder-join">
      {state === "done" ? (
        <span className="muted small" role="status">
          {join.done}
        </span>
      ) : (
        <Button size="small" variant="primary" loading={state === "busy"} aria-label={`${join.label}: ${team.name || "team"}`} onClick={() => void run()}>
          {join.label}
        </Button>
      )}
      {error && (
        <span className="form-error small" role="alert">
          {error}
        </span>
      )}
    </span>
  );
}
