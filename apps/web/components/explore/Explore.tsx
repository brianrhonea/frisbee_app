"use client";
// Explore (ExploreScreen): one search box for players, teams, groups and
// tournaments, with the app's filter chips; then upcoming tournaments,
// recent results, a rankings preview and shortcuts. Players and teams come
// from /v1/public/search; tournaments are matched in the browser over the
// upcoming ones the card already reads, as the app's ExploreViewModel does.
import type { PublicListing, PublicProfile, SearchPage, TournamentDoc } from "@stall10/shared";
import { where } from "firebase/firestore";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { listingSubtitle } from "@/lib/site";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { type DivisionRanking, type PlayerRanking, rankingLabel, rankingOrder, whole } from "../Rankings";
import { datesLabel, TournamentCard, tournamentHref, useUpcomingTournaments } from "../tournaments/TournamentLists";
import { type ExploreFilter, exploreHref, listingsFor, matchTournaments, minQueryLength } from "./filters";
import "./explore.css";

const chips: Array<[string, ExploreFilter | null]> = [
  ["All", null],
  ["Players", "players"],
  ["Teams", "teams"],
  ["Groups", "groups"],
  ["Tournaments", "tournaments"],
];

/** Tournaments and results the cards show (ExploreViewModel.previewCount). */
const previewCount = 4;
/** Rankings the preview shows (ExploreViewModel.previewTeams). */
const previewTeams = 5;
/** Upcoming tournaments Explore reads (watchUpcoming(limit: 30)). */
const upcomingLimit = 30;

export function Explore({ initialQuery, initialFilter }: { initialQuery: string; initialFilter: ExploreFilter | null }) {
  const { user } = useAuth();
  const upcoming = useUpcomingTournaments(upcomingLimit);
  const mine = useLiveQuery<{ kind?: string; level?: string; division?: string }>(
    user ? "teams" : null,
    user ? [where("memberIds", "array-contains", user.uid)] : [],
    user?.uid ?? "",
  );
  return (
    <div className="explore">
      <SearchCard initialQuery={initialQuery} initialFilter={initialFilter} upcoming={upcoming.list} mine={mine.data ?? []} />
      <UpcomingCard list={upcoming.list} error={upcoming.error} />
      <RankingsPreview mine={mine.data ?? []} />
      <RecentResults />
      <JumpIn />
    </div>
  );
}

type MyTeam = Doc<{ kind?: string; level?: string; division?: string }>;

function SearchCard({
  initialQuery,
  initialFilter,
  upcoming,
  mine,
}: {
  initialQuery: string;
  initialFilter: ExploreFilter | null;
  upcoming: Array<Doc<TournamentDoc>> | undefined;
  mine: MyTeam[];
}) {
  const { user } = useAuth();
  const router = useRouter();
  const [text, setText] = useState(initialQuery);
  const [query, setQuery] = useState(initialQuery.trim());
  const [only, setOnly] = useState<ExploreFilter | null>(initialFilter);
  const [found, setFound] = useState<{ q: string; page: SearchPage | null } | null>(null);
  // Bumped to rerun a failed search for the same text.
  const [retry, setRetry] = useState(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // What this card last put in the address, so its own updates don't rewrite the box.
  const pushed = useRef(initialQuery.trim());
  // A link or the browser's back button lands here with another ?q=.
  useEffect(() => {
    if (initialQuery.trim() === pushed.current) return;
    pushed.current = initialQuery.trim();
    setText(initialQuery);
    setQuery(initialQuery.trim());
  }, [initialQuery]);
  useEffect(() => setOnly(initialFilter), [initialFilter]);
  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  const ready = query.length >= minQueryLength;
  useEffect(() => {
    if (!user || !ready) return;
    let live = true;
    callApi<SearchPage>(user, `/v1/public/search?q=${encodeURIComponent(query)}`).then(
      (page) => live && setFound({ q: query, page }),
      () => live && setFound({ q: query, page: null }),
    );
    return () => {
      live = false;
    };
  }, [user, query, ready, retry]);

  function search(next: string, filter = only) {
    if (timer.current) clearTimeout(timer.current);
    // The same text after "Couldn't search": try it again.
    if (next.trim() === query && found?.q === query && found.page === null) {
      setFound(null);
      setRetry((n) => n + 1);
    }
    setQuery(next.trim());
    pushed.current = next.trim();
    router.replace(exploreHref(next, filter), { scroll: false });
  }
  function onType(next: string) {
    setText(next);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => search(next), 300);
  }
  function pick(filter: ExploreFilter | null) {
    setOnly(filter);
    router.replace(exploreHref(query, filter), { scroll: false });
  }

  const all = only === null;
  const teamsShown = all || only === "teams" || only === "groups";
  const playersShown = all || only === "players";
  const tournamentsShown = all || only === "tournaments";
  const current = found && found.q === query ? found : null;
  // Tournaments are matched here, so only players and teams wait on the search.
  const running = ready && !current && (playersShown || teamsShown);
  const failed = ready && current?.page === null;
  const people: PublicProfile[] = ready && playersShown ? (current?.page?.players ?? []) : [];
  const teams: PublicListing[] = ready && teamsShown ? listingsFor(current?.page?.teams ?? [], only) : [];
  const events = useMemo(() => (ready && tournamentsShown ? matchTournaments(upcoming ?? [], query) : []), [ready, tournamentsShown, upcoming, query]);
  const nothing = people.length === 0 && teams.length === 0 && events.length === 0;
  const sections = [people.length, teams.length, events.length].filter((n) => n > 0).length;
  const myIds = new Set(mine.map((t) => t.id));

  return (
    <section className="card explore-search" aria-labelledby="explore-search-title">
      <h2 className="card-title" id="explore-search-title">
        Search
      </h2>
      <form
        className="search-form explore-search-form"
        role="search"
        onSubmit={(e) => {
          e.preventDefault();
          search(text);
        }}
      >
        <label className="visually-hidden" htmlFor="q">
          Search Stall 10
        </label>
        <input id="q" name="q" type="search" value={text} onChange={(e) => onType(e.target.value)} placeholder="Search Stall 10" autoComplete="off" enterKeyHint="search" />
        <button className="btn btn-primary" type="submit">
          Search
        </button>
      </form>
      <div className="segmented explore-chips" role="group" aria-label="Show">
        {chips.map(([label, filter]) => (
          <button key={label} type="button" className={only === filter ? "on" : ""} aria-pressed={only === filter} onClick={() => pick(filter)}>
            {label}
          </button>
        ))}
      </div>
      <div className="explore-results" aria-live="polite">
        {running && nothing ? (
          <p className="muted" aria-busy="true">
            Searching…
          </p>
        ) : failed && nothing && (playersShown || teamsShown) ? (
          <p className="form-error">Couldn&apos;t search. Try again.</p>
        ) : ready && nothing ? (
          <div className="empty">
            <b>Nothing found</b>
            <br />
            Try another word from a name, username, city, school, team or tournament.
          </div>
        ) : nothing ? (
          <p className="muted explore-hint">Type at least {minQueryLength} letters to search players, teams, groups and tournaments.</p>
        ) : null}
        {people.length > 0 && (
          <>
            {sections > 1 && <h3 className="explore-heading">Players</h3>}
            <div className="stack explore-list">
              {people.map((p) => (
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
        {teams.length > 0 && (
          <>
            {sections > 1 && <h3 className="explore-heading">Teams and groups</h3>}
            <div className="stack explore-list">
              {teams.map((t) => {
                const group = (t.kind ?? "team") !== "team";
                const sub = listingSubtitle(t);
                return (
                  <Link key={t.id} className="row-card" href={`/teams/${encodeURIComponent(t.id)}`}>
                    <Avatar name={t.name} />
                    <span>
                      <b>{t.name || "Team"}</b>
                      <small>{group ? [sub, t.requiresApproval ? "Approval required" : "Open to join"].filter(Boolean).join(" · ") : sub}</small>
                    </span>
                    {myIds.has(t.id) && <span className="pill pill-soft explore-mine">{group ? "Your group" : "Your team"}</span>}
                  </Link>
                );
              })}
            </div>
          </>
        )}
        {events.length > 0 && (
          <>
            {sections > 1 && <h3 className="explore-heading">Tournaments</h3>}
            <div className="stack explore-list">
              {events.map((t) => (
                <TournamentCard key={t.id} t={t} />
              ))}
            </div>
          </>
        )}
      </div>
    </section>
  );
}

/** The next few published tournaments, with a link to all of them (UpcomingTournamentsCard). */
function UpcomingCard({ list, error }: { list: Array<Doc<TournamentDoc>> | undefined; error: string | null }) {
  const shown = (list ?? []).slice(0, previewCount);
  return (
    <section className="card">
      <div className="card-head">
        <h2 className="card-title">Tournaments &amp; leagues</h2>
        <Link href="/tournaments" className="explore-card-link">
          See all
        </Link>
      </div>
      {error ? (
        <p className="form-error">{error}</p>
      ) : !list ? (
        <p className="muted" aria-busy="true">
          Loading…
        </p>
      ) : shown.length === 0 ? (
        <p className="muted small">Nothing coming up yet. Groups and clubs host tournaments and leagues from their Tournaments tab.</p>
      ) : (
        <div className="stack explore-list">
          {shown.map((t) => (
            <TournamentCard key={t.id} t={t} />
          ))}
        </div>
      )}
    </section>
  );
}

interface PlacedTeam {
  teamId?: string;
  name?: string;
}
interface TournamentResult {
  tournamentId?: string;
  name?: string;
  hostName?: string;
  location?: string;
  startsOn?: string;
  endsOn?: string;
  divisions?: Array<{ label?: string; champion?: PlacedTeam | null; runnerUp?: PlacedTeam | null }>;
}

/** Champions of recently finished public tournaments (RecentResultsCard); hidden until one has finished. */
function RecentResults() {
  const { user } = useAuth();
  const doc = useLiveDoc<{ tournaments?: TournamentResult[] }>(user ? "tournamentResults/recent" : null);
  const list = (doc.data?.tournaments ?? []).filter((r) => r.tournamentId).slice(0, previewCount);
  if (list.length === 0) return null;
  return (
    <section className="card">
      <h2 className="card-title">Recent results</h2>
      <ul className="explore-results-list">
        {list.map((r) => {
          const ended = r.endsOn ?? r.startsOn;
          return (
            <li key={r.tournamentId}>
              <Link href={tournamentHref(r.tournamentId!)} className="explore-result">
                <b>{r.name || "Tournament"}</b>
                <small className="muted">{[ended ? datesLabel(ended, null) : "", r.hostName, r.location].filter(Boolean).join(" · ")}</small>
                {(r.divisions ?? []).map((d, i) => (
                  <span key={`${d.label}${i}`} className="explore-champion">
                    <span aria-hidden="true">🏆</span> <b>{d.champion?.name ?? ""}</b>
                    <span className="muted"> {[d.label, d.runnerUp?.name ? `over ${d.runnerUp.name}` : ""].filter(Boolean).join(" · ")}</span>
                  </span>
                ))}
              </Link>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

/**
 * The top of one division's ranking, or of the player ranking
 * (RankingsPreviewCard): the one picked, else the division of the
 * viewer's first team that has one, else the biggest.
 */
function RankingsPreview({ mine }: { mine: MyTeam[] }) {
  const { user } = useAuth();
  const [kind, setKind] = useState<"teams" | "players">("teams");
  const [picked, setPicked] = useState<string | null>(null);
  const rankings = useLiveQuery<DivisionRanking>(user ? "rankings" : null, [], "rankings");
  const players = useLiveDoc<PlayerRanking>(user && kind === "players" ? "playerRankings/all" : null);
  const ranked = (rankings.data ?? []).filter((r) => (r.teams?.length ?? 0) > 0).sort((a, b) => rankingOrder(a) - rankingOrder(b));
  const byKey = (key: string | null | undefined) => ranked.find((r) => r.id === key);
  const mineKeys = mine.filter((t) => (t.kind ?? "team") === "team").map((t) => `${t.level ?? "club"}-${t.division ?? "mixed"}`);
  const ranking =
    byKey(picked) ?? mineKeys.map(byKey).find(Boolean) ?? [...ranked].sort((a, b) => (b.teams?.length ?? 0) - (a.teams?.length ?? 0))[0];
  const myIds = new Set(mine.map((t) => t.id));
  const link = kind === "players" ? "/rankings?kind=players" : ranking ? `/rankings?division=${encodeURIComponent(ranking.id)}` : null;

  return (
    <section className="card">
      <div className="card-head">
        <h2 className="card-title">Rankings</h2>
        {link && (
          <Link href={link} className="explore-card-link">
            Full rankings
          </Link>
        )}
      </div>
      <div className="segmented" role="group" aria-label="Rank">
        {(["teams", "players"] as const).map((k) => (
          <button key={k} type="button" className={kind === k ? "on" : ""} aria-pressed={kind === k} onClick={() => setKind(k)}>
            {k === "teams" ? "Teams" : "Players"}
          </button>
        ))}
      </div>
      {kind === "teams" ? (
        rankings.error ? (
          <p className="form-error">{rankings.error}</p>
        ) : !rankings.data ? (
          <p className="muted" aria-busy="true">
            Loading…
          </p>
        ) : !ranking ? (
          <p className="muted small">Teams get ranked once they play 5 games in public tournaments hosted on Stall 10.</p>
        ) : (
          <>
            {ranked.length > 1 ? (
              <div className="explore-divisions" role="group" aria-label="Division">
                {ranked.map((r) => (
                  <button key={r.id} type="button" className={`explore-division${r.id === ranking.id ? " on" : ""}`} aria-pressed={r.id === ranking.id} onClick={() => setPicked(r.id)}>
                    {rankingLabel(r)}
                  </button>
                ))}
              </div>
            ) : (
              <p className="explore-eyebrow">{rankingLabel(ranking)}</p>
            )}
            <ol className="explore-ranks">
              {(ranking.teams ?? []).slice(0, previewTeams).map((t) => (
                <li key={t.teamId || t.rank} className={myIds.has(t.teamId) ? "mine" : ""}>
                  <span className={`explore-rank${t.rank <= 3 ? " top" : ""}`}>{whole(t.rank)}</span>
                  {t.teamId ? <Link href={`/teams/${encodeURIComponent(t.teamId)}`}>{t.name}</Link> : <span>{t.name}</span>}
                  <span className="muted explore-num">
                    {whole(t.wins)}–{whole(t.losses)}
                  </span>
                  <b className="explore-num">{whole(t.rating)}</b>
                </li>
              ))}
            </ol>
          </>
        )
      ) : players.error ? (
        <p className="form-error">{players.error}</p>
      ) : players.data === undefined ? (
        <p className="muted" aria-busy="true">
          Loading…
        </p>
      ) : (players.data?.players ?? []).length === 0 ? (
        <p className="muted small">
          Players get rated once their team logs 10 of their games with the stat tracker. Only public profiles that show stats are rated.
        </p>
      ) : (
        <ol className="explore-ranks">
          {(players.data?.players ?? []).slice(0, previewTeams).map((p) => (
            <li key={p.uid || p.rank} className={p.uid === user?.uid ? "mine" : ""}>
              <span className={`explore-rank${p.rank <= 3 ? " top" : ""}`}>{whole(p.rank)}</span>
              <Link href={`/players/${encodeURIComponent(p.uid)}`} className="explore-player">
                <Avatar name={p.name} url={p.photoUrl} size={24} />
                <span>{p.name}</span>
              </Link>
              <span className="muted explore-num">{whole(p.games)} gp</span>
              <b className="explore-num">{whole(p.rating)}</b>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}

const shortcuts = [
  { href: "/learn", title: "Learn to play", sub: "The rules of ultimate in five minutes" },
  { href: "/tournaments", title: "Find a tournament or league", sub: "Apply with your team, sign up to play, or follow results" },
  { href: "/tournaments/host", title: "Host a league or tournament", sub: "Run it from your group or school or club" },
  { href: "/teams/new", title: "Start a team", sub: "Roster, playbook, stats and chat" },
  { href: "/teams/new?kind=community", title: "Start a pickup group", sub: "Open sign-ups, pickup and tournaments" },
];

/** Shortcuts (Jump in). */
function JumpIn() {
  return (
    <section className="card">
      <h2 className="card-title">Jump in</h2>
      <div className="stack explore-list">
        {shortcuts.map((s) => (
          <Link key={s.title} className="row-card" href={s.href}>
            <span>
              <b>{s.title}</b>
              <small>{s.sub}</small>
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
}
