"use client";
// Discover (the app's Discover tab, which replaced Explore and Find
// events): one search box for tournaments, leagues, pickup, teams,
// communities and (members only) players, with filter chips; then what's
// live now, what's coming up, rankings, results and shortcuts.
//
// Visitors can look around and search without an account: teams and
// communities come from `/v1/public/teams?q=`, tournaments and leagues
// from the public list the server rendered (`/v1/public/tournaments`),
// public team events from `/v1/public/events`. Members search players and
// teams through `/v1/public/search` with their token and read tournaments
// live, as the app's ExploreViewModel does.
import {
  type EventsPage,
  hostedType,
  isLiveGame,
  orderedRankingKeys,
  parseRankingKey,
  type PublicHostedCard,
  type PublicHostedList,
  type PublicListing,
  type PublicLiveGame,
  type PublicProfile,
  rankingsHref,
  type SearchPage,
  type TeamSearchPage,
} from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { callApi, getPublicApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { listingSubtitle } from "@/lib/site";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { EventItem } from "../EventItem";
import { EventsBrowser } from "../EventsBrowser";
import { LocalTime } from "../LocalTime";
import { type DivisionRanking, isShownRanking, type PlayerRanking, rankingLabel, whole } from "../Rankings";
import { ScheduleLink } from "../ScheduleLink";
import { type CardTournament, datesLabel, TournamentCard, tournamentHref, useUpcomingTournaments } from "../tournaments/TournamentLists";
import { usePublicEvents } from "../usePublicEvents";
import { type ExploreFilter, eventsFor, exploreHref, hostedFor, listingsFor, matchText, matchTournaments, minQueryLength } from "./filters";
import "./explore.css";
import { useMyTeams } from "../useMyTeams";
import { StatusPill } from "../ui/StatusPill";
import { FilterChips } from "../ui/FilterChips";
import { ErrorNote } from "@/components/StatusViews";

const chips: Array<[string, ExploreFilter | null]> = [
  ["All", null],
  ["Tournaments", "tournaments"],
  ["Leagues", "leagues"],
  ["Pickup", "pickup"],
  ["Teams", "teams"],
  ["Communities", "groups"],
];
/** Members also search players. */
const playersChip: [string, ExploreFilter] = ["Players", "players"];

/** What a chip searches, for the hint before typing (the app's Discover hint). */
function searchHint(only: ExploreFilter | null, member: boolean): string {
  switch (only) {
    case "tournaments":
      return "tournaments and hat tournaments";
    case "leagues":
      return "leagues";
    case "pickup":
      return "pickup communities and pickup games";
    case "teams":
      return "teams";
    case "groups":
      return "communities, schools and clubs";
    case "players":
      return "players by name or username";
    default:
      return member ? "players, teams, communities, tournaments and leagues" : "tournaments, leagues, pickup, teams and communities";
  }
}

/** Tournaments and results the cards show (ExploreViewModel.previewCount). */
const previewCount = 4;
/** Rankings the preview shows (ExploreViewModel.previewTeams). */
const previewTeams = 5;
/** Upcoming tournaments Discover reads (watchUpcoming(limit: 30)). */
const upcomingLimit = 30;

type PublicTeamEvent = EventsPage["events"][number];

/**
 * Discover. [tournaments] and [events] are the public lists the server
 * read, so visitors (and everyone while sign-in loads) see them at once;
 * members then get tournaments live.
 */
export function Discover({
  initialQuery,
  initialFilter,
  tournaments,
  events,
}: {
  initialQuery: string;
  initialFilter: ExploreFilter | null;
  tournaments: PublicHostedCard[] | null;
  events: EventsPage | null;
}) {
  const { user } = useAuth();
  const upcoming = useUpcomingTournaments(upcomingLimit);
  const mine = useMyTeams<{ kind?: string; level?: string; division?: string }>(user?.uid);
  const fresh = usePublicEvents();
  const [only, setOnly] = useState<ExploreFilter | null>(initialFilter);
  useEffect(() => setOnly(initialFilter), [initialFilter]);
  // Visitors can't filter to people; the chip isn't theirs.
  const filter = only === "players" && user === null ? null : only;

  // Members' live list once it's in; until then (and for visitors) the server's.
  const hosted: CardTournament[] | undefined = user && upcoming.list ? upcoming.list : (tournaments ?? (user === null ? [] : undefined));
  const hostedError = user ? upcoming.error : tournaments === null ? "Couldn't load tournaments. Try again in a minute." : null;
  const publicEvents = fresh ?? events ?? (fresh === null ? null : undefined);

  return (
    <div className="explore">
      <SearchCard
        initialQuery={initialQuery}
        only={filter}
        setOnly={setOnly}
        hosted={hosted ?? []}
        events={publicEvents ?? null}
        mine={mine.data ?? []}
      />
      <LiveNow list={filter === null || filter === "tournaments" || filter === "leagues" ? hostedFor(hosted ?? [], filter) : []} initial={tournaments} />
      <ComingUp only={filter} hosted={hosted} error={hostedError} events={publicEvents} />
      {user ? <RankingsPreview mine={mine.data ?? []} /> : <RankingsLink />}
      <RecentResults />
      <JumpIn />
    </div>
  );
}

type MyTeam = Doc<{ kind?: string; level?: string; division?: string }>;

/** Who's searching: a member's players and teams, or a visitor's teams only. */
type Found = { q: string; players: PublicProfile[]; teams: PublicListing[] } | { q: string; failed: true };

function SearchCard({
  initialQuery,
  only,
  setOnly,
  hosted,
  events,
  mine,
}: {
  initialQuery: string;
  only: ExploreFilter | null;
  setOnly: (f: ExploreFilter | null) => void;
  hosted: CardTournament[];
  events: EventsPage | null;
  mine: MyTeam[];
}) {
  const { user } = useAuth();
  const router = useRouter();
  const [text, setText] = useState(initialQuery);
  const [query, setQuery] = useState(initialQuery.trim());
  const [found, setFound] = useState<Found | null>(null);
  // Bumped to rerun a failed search for the same text.
  const [retry, setRetry] = useState(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // What this card last put in the address, so its own updates don't rewrite the box.
  const pushed = useRef(initialQuery.trim());
  // A link, the top bar's search or the browser's back button lands here with another ?q=.
  useEffect(() => {
    if (initialQuery.trim() === pushed.current) return;
    pushed.current = initialQuery.trim();
    setText(initialQuery);
    setQuery(initialQuery.trim());
  }, [initialQuery]);
  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  const all = only === null;
  const peopleShown = !!user && (all || only === "players");
  const listingsShown = all || only === "teams" || only === "groups" || only === "pickup";
  const ready = query.length >= minQueryLength;
  // Players and teams come from the API; everything else is matched here.
  const needsApi = peopleShown || listingsShown;
  useEffect(() => {
    // Still finding out whether someone's signed in.
    if (user === undefined || !ready || !needsApi) return;
    let live = true;
    const q = encodeURIComponent(query);
    const page: Promise<{ players: PublicProfile[]; teams: PublicListing[] }> = user
      ? callApi<SearchPage>(user, `/v1/public/search?q=${q}`)
      : getPublicApi<TeamSearchPage>(null, `/v1/public/teams?q=${q}`).then((p) => ({ players: [], teams: p.teams }));
    page.then(
      (p) => live && setFound({ q: query, players: p.players, teams: p.teams }),
      () => live && setFound({ q: query, failed: true }),
    );
    return () => {
      live = false;
    };
  }, [user, query, ready, needsApi, retry]);

  function search(next: string, filter = only) {
    if (timer.current) clearTimeout(timer.current);
    // The same text after "Couldn't search": try it again.
    if (next.trim() === query && found?.q === query && "failed" in found) {
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

  const current = found && found.q === query ? found : null;
  const failed = ready && !!current && "failed" in current;
  const running = ready && needsApi && !current;
  const people: PublicProfile[] = ready && peopleShown && current && !("failed" in current) ? current.players : [];
  const teams: PublicListing[] = ready && listingsShown && current && !("failed" in current) ? listingsFor(current.teams, only) : [];
  const tournaments = useMemo(() => (ready ? matchTournaments(hostedFor(hosted, only), query) : []), [ready, hosted, only, query]);
  const groupTournaments = useMemo(
    () => (ready && (all || only === "tournaments") ? matchText(events?.tournaments ?? [], query, (t) => t.name ?? "") : []),
    [ready, all, only, events, query],
  );
  const teamEvents = useMemo(
    () => (ready ? matchText(eventsFor(events?.events ?? [], only), query, (e) => `${e.title ?? ""} ${e.teamName} ${e.location ?? ""}`) : []),
    [ready, only, events, query],
  );
  // Grouped by kind as the app's Discover: tournaments, leagues, teams, communities, players (then the website's events).
  const cups = tournaments.filter((t) => hostedType(t) !== "league");
  const leagues = tournaments.filter((t) => hostedType(t) === "league");
  const teamListings = teams.filter((t) => (t.kind ?? "team") === "team");
  const groups = teams.filter((t) => (t.kind ?? "team") !== "team");
  const counts = [cups.length + groupTournaments.length, leagues.length, teamListings.length, groups.length, people.length, teamEvents.length];
  const nothing = counts.every((n) => n === 0);
  const sections = counts.filter((n) => n > 0).length;
  const myIds = new Set(mine.map((t) => t.id));
  const shownChips = user ? [...chips, playersChip] : chips;
  const what = searchHint(only, !!user);
  const heading = (title: string) => (sections > 1 ? <h3 className="explore-heading">{title}</h3> : null);
  const listingRows = (list: PublicListing[]) => (
    <div className="stack explore-list">
      {list.map((t) => {
        const group = (t.kind ?? "team") !== "team";
        const sub = listingSubtitle(t);
        return (
          <Link key={t.id} className="row-card" href={`/teams/${encodeURIComponent(t.id)}`}>
            <Avatar name={t.name} />
            <span>
              <b>{t.name || "Team"}</b>
              <small>{group ? [sub, t.requiresApproval ? "Approval required" : "Open to join"].filter(Boolean).join(" · ") : sub}</small>
            </span>
            {myIds.has(t.id) && <StatusPill className="explore-mine">{group ? "Your group" : "Your team"}</StatusPill>}
          </Link>
        );
      })}
    </div>
  );

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
      <FilterChips
        className="explore-chips"
        label="Show"
        items={shownChips.map(([label]) => ({ id: label, label }))}
        value={shownChips.find(([, filter]) => filter === only)?.[0] ?? ""}
        onChange={(label) => pick(shownChips.find(([l]) => l === label)?.[1] ?? null)}
      />
      {user === null && (
        <p className="muted small explore-people-note">
          Looking for a player? <Link href={`/sign-in?next=${encodeURIComponent(exploreHref(query, "players"))}`}>Log in to search people</Link>.
        </p>
      )}
      <div className="explore-results" aria-live="polite">
        {running && nothing ? (
          <p className="muted" aria-busy="true">
            Searching…
          </p>
        ) : failed && nothing ? (
          <ErrorNote>Couldn&apos;t search. Try again.</ErrorNote>
        ) : ready && nothing ? (
          <div className="empty">
            <b>Nothing found</b>
            <br />
            Try another word from a name, {user ? "username, " : ""}city, school, team, tournament or league.
          </div>
        ) : nothing ? (
          <p className="muted explore-hint">
            Type at least {minQueryLength} letters to search {what}.
          </p>
        ) : null}
        {cups.length + groupTournaments.length > 0 && (
          <>
            {heading("Tournaments")}
            <div className="stack explore-list">
              {cups.map((t) => (
                <TournamentCard key={t.id} t={t} />
              ))}
              {groupTournaments.map((t) => (
                <GroupTournamentRow key={t.id} t={t} />
              ))}
            </div>
          </>
        )}
        {leagues.length > 0 && (
          <>
            {heading("Leagues")}
            <div className="stack explore-list">
              {leagues.map((t) => (
                <TournamentCard key={t.id} t={t} />
              ))}
            </div>
          </>
        )}
        {teamListings.length > 0 && (
          <>
            {heading("Teams")}
            {listingRows(teamListings)}
          </>
        )}
        {groups.length > 0 && (
          <>
            {heading(only === "pickup" ? "Pickup communities" : "Communities")}
            {listingRows(groups)}
          </>
        )}
        {people.length > 0 && (
          <>
            {heading("Players")}
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
        {teamEvents.length > 0 && (
          <>
            {heading(only === "pickup" ? "Pickup games" : "Events")}
            <div className="stack explore-list">
              {teamEvents.map((e) => (
                <TeamEventRow key={`${e.teamId}/${e.id}`} e={e} />
              ))}
            </div>
          </>
        )}
      </div>
    </section>
  );
}

/** A community's own tournament (group tournaments): its page for members, the community's for visitors. */
function GroupTournamentRow({ t }: { t: EventsPage["tournaments"][number] }) {
  const { user } = useAuth();
  const href =
    t.groupId && t.tournamentId && user
      ? `/teams/${encodeURIComponent(t.groupId)}/tournaments/${encodeURIComponent(t.tournamentId)}`
      : t.groupId
        ? `/teams/${encodeURIComponent(t.groupId)}`
        : "/explore#coming-up";
  return (
    <Link className="row-card" href={href}>
      <span>
        <b>{t.name || "Tournament"}</b>
        <small>
          <LocalTime iso={t.startsAt} />
          {t.endsOn && t.endsOn !== t.startsAt?.slice(0, 10) ? ` – ${t.endsOn}` : ""}
        </small>
      </span>
    </Link>
  );
}

/** A public team event (a pickup game, a practice open to all) in the results. */
function TeamEventRow({ e }: { e: PublicTeamEvent }) {
  return (
    <EventItem startsAt={e.startsAt}>
      <Link href={`/teams/${encodeURIComponent(e.teamId)}/schedule?event=${encodeURIComponent(e.id)}`}>
        <b>{e.title || "Event"}</b>
      </Link>
      <small>
        <LocalTime iso={e.startsAt} style="dateTime" />
        {e.location ? ` · ${e.location}` : ""}
      </small>
      <small>
        <Link href={`/teams/${encodeURIComponent(e.teamId)}`}>{e.teamName}</Link>
      </small>
    </EventItem>
  );
}

/** Live games a Live now card lists before "+N more live". */
const liveShown = 3;
/** How often Live now rereads the running scores while something is live. */
const liveRefreshMs = 60_000;

/**
 * Each live event's games being played now (card.liveGames of
 * `GET /v1/public/tournaments`), by event id: the server's list first,
 * then reread each minute while any event is live (members' list is
 * live from Firestore, without the games).
 */
function useLiveGames(initial: PublicHostedCard[] | null, anyLive: boolean): Map<string, PublicLiveGame[]> {
  const { user } = useAuth();
  const [cards, setCards] = useState<PublicHostedCard[] | null>(initial);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => setCards(initial), [initial]);
  useEffect(() => {
    if (!anyLive || user === undefined) return;
    let on = true;
    const read = () =>
      getPublicApi<PublicHostedList>(user, "/v1/public/tournaments").then(
        (l) => {
          if (!on) return;
          setCards(l.tournaments);
          setNow(Date.now());
        },
        () => {},
      );
    // Members' first read (the server's page is up to a minute old), then every minute.
    if (user) void read();
    const timer = setInterval(() => void read(), liveRefreshMs);
    return () => {
      on = false;
      clearInterval(timer);
    };
  }, [anyLive, user]);
  return useMemo(() => {
    const m = new Map<string, PublicLiveGame[]>();
    for (const c of cards ?? []) {
      // Still fresh (isLiveGame) at the time it was read or since.
      const games = (c.liveGames ?? []).filter((g) => isLiveGame({ status: "scheduled", live: { scoreA: g.scoreA, scoreB: g.scoreB, updatedAt: g.updatedAt } }, now));
      if (games.length > 0) m.set(c.id, games);
    }
    return m;
  }, [cards, now]);
}

/** Hosted tournaments and leagues being played right now, with their live games and a link to each one's scores; hidden when none are. */
function LiveNow({ list, initial }: { list: CardTournament[] | undefined; initial: PublicHostedCard[] | null }) {
  const live = (list ?? []).filter((t) => t.status === "live");
  const games = useLiveGames(initial, live.length > 0);
  if (live.length === 0) return null;
  return (
    <section className="card explore-live" aria-labelledby="live-now-title">
      <h2 className="card-title" id="live-now-title">
        <span className="live-dot" aria-hidden="true" />
        Live now
      </h2>
      <div className="stack explore-list">
        {live.map((t) => {
          const rows = games.get(t.id) ?? [];
          return (
            <div key={t.id} className="explore-live-event">
              <TournamentCard t={t} />
              {rows.length > 0 && (
                <ul className="explore-live-games">
                  {rows.slice(0, liveShown).map((g) => (
                    <li key={`${g.divisionId}/${g.gameId}`}>
                      <span className="live-dot live-dot-small" aria-hidden="true" />
                      <span className="explore-live-name explore-live-a">{g.nameA}</span>
                      <b className="explore-live-score">
                        {g.scoreA}–{g.scoreB}
                      </b>
                      <span className="explore-live-name">{g.nameB}</span>
                      <small>· Field {g.field}</small>
                    </li>
                  ))}
                  {rows.length > liveShown && <li className="explore-live-more">+{rows.length - liveShown} more live</li>}
                </ul>
              )}
            </div>
          );
        })}
      </div>
    </section>
  );
}

/**
 * What's coming up (the old Events page and Find tournaments): the next
 * hosted tournaments and leagues, then public team events and community
 * tournaments on a week strip. The chips narrow it as they do the search.
 */
function ComingUp({
  only,
  hosted,
  error,
  events,
}: {
  only: ExploreFilter | null;
  hosted: CardTournament[] | undefined;
  error: string | null;
  events: EventsPage | null | undefined;
}) {
  const showHosted = only === null || only === "tournaments" || only === "leagues";
  const showEvents = only === null || only === "pickup";
  if (!showHosted && !showEvents) return null;
  // Live ones are under Live now.
  const shown = hostedFor(hosted ?? [], only)
    .filter((t) => t.status !== "live")
    .slice(0, previewCount);
  const title = only === "leagues" ? "Leagues" : only === "tournaments" ? "Tournaments" : "Tournaments & leagues";
  return (
    <section className="explore-coming" id="coming-up" aria-labelledby="coming-up-title">
      <div className="explore-section-head">
        <h2 className="section-title" id="coming-up-title">
          Coming up
        </h2>
        <ScheduleLink />
      </div>
      {showHosted && (
        <section className="card">
          <div className="card-head">
            <h3 className="card-title">{title}</h3>
            <Link href="/tournaments" className="explore-card-link">
              See all
            </Link>
          </div>
          {error && !hosted ? (
            <ErrorNote>{error}</ErrorNote>
          ) : !hosted ? (
            <p className="muted" aria-busy="true">
              Loading…
            </p>
          ) : shown.length === 0 ? (
            <p className="muted small">Nothing coming up yet. Communities and clubs host tournaments and leagues from their Tournaments tab.</p>
          ) : (
            <div className="stack explore-list">
              {shown.map((t) => (
                <TournamentCard key={t.id} t={t} />
              ))}
            </div>
          )}
        </section>
      )}
      {showEvents &&
        (events === undefined ? (
          <p className="muted" aria-busy="true">
            Loading events…
          </p>
        ) : events === null ? (
          <ErrorNote>Couldn&apos;t load events. Try again.</ErrorNote>
        ) : (
          <EventsBrowser
            events={eventsFor(events.events, only)}
            tournaments={only === "pickup" ? [] : events.tournaments}
          />
        ))}
    </section>
  );
}

/** Visitors: the rankings are public, on their own page. */
function RankingsLink() {
  return (
    <section className="card">
      <div className="card-head">
        <h2 className="card-title">Rankings</h2>
        <Link href="/rankings" className="explore-card-link">
          See rankings
        </Link>
      </div>
      <p className="muted small">Club, college, league and pickup teams ranked by their games in tournaments hosted on Stall 10.</p>
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
  // Never youth (isShownRanking), by level then division.
  const shown = (rankings.data ?? []).filter(isShownRanking);
  const ranked = orderedRankingKeys(shown.map((r) => r.id)).map((k) => shown.find((r) => r.id === k)!);
  const byKey = (key: string | null | undefined) => ranked.find((r) => r.id === key);
  const mineKeys = mine.filter((t) => (t.kind ?? "team") === "team").map((t) => `${t.level ?? "club"}-${t.division ?? "mixed"}`);
  const ranking =
    byKey(picked) ?? mineKeys.map(byKey).find(Boolean) ?? [...ranked].sort((a, b) => (b.teams?.length ?? 0) - (a.teams?.length ?? 0))[0];
  const myIds = new Set(mine.map((t) => t.id));
  const at = ranking ? parseRankingKey(ranking.id) : null;
  const link = kind === "players" ? "/rankings?kind=players" : at ? rankingsHref(at.level, at.division) : null;

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
          <ErrorNote>{rankings.error}</ErrorNote>
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
        <ErrorNote>{players.error}</ErrorNote>
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
  { href: "/tournaments/host", title: "Host a league or tournament", sub: "Run it from your team or community" },
  { href: "/teams/new", title: "Start a team", sub: "Roster, playbook, stats and chat" },
  { href: "/teams/new?kind=community", title: "Start a pickup community", sub: "Open sign-ups, pickup and tournaments" },
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
