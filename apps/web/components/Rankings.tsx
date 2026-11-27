"use client";
import {
  chooseRanking,
  type Division,
  parseRankingKey,
  type PublicDivisionRanking,
  type RankedLevel,
  rankedLevelLabels,
  type RankingChoice,
  rankingDivisionLabels,
  rankingLabel as labelFor,
  rankingsHref,
  type RankingWant,
} from "@stall10/shared";
import Link from "next/link";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { MembersOnly } from "./MembersOnly";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { formatDateTime } from "@/lib/dates";
import { ErrorNote } from "@/components/StatusViews";

// Stall 10's own rankings (the `rankings` Cloud Functions, nightly), as the
// app's Rankings screen shows them: rankings/{level-division} for teams and
// playerRankings/all for players. Members read them live from Firestore
// (firestore.rules lets them); visitors get the team rankings the server
// rendered from the API's `/v1/public/rankings`, and a sign-up prompt for
// players. Youth is never ranked or shown: the functions skip it, the API
// leaves it out, and the live reads drop a youth key too.

interface RankedTeam {
  rank: number;
  teamId: string;
  name: string;
  rating: number;
  wins: number;
  losses: number;
}
export interface DivisionRanking {
  level?: string;
  division?: string;
  teams?: RankedTeam[];
  minGames?: number;
  updatedAt?: string;
}
interface RankedPlayer {
  rank: number;
  uid: string;
  name: string;
  username?: string;
  photoUrl?: string;
  rating: number;
  games: number;
}
export interface PlayerRanking {
  players?: RankedPlayer[];
  minGames?: number;
  updatedAt?: string;
}

/** Whether a live ranking doc is shown: a ranked key (never youth) that says the same as its id, with teams. */
export function isShownRanking(r: Doc<DivisionRanking>): boolean {
  const p = parseRankingKey(r.id);
  return !!p && r.level === p.level && r.division === p.division && (r.teams?.length ?? 0) > 0;
}

/** "Club Mixed" for a live doc. */
export const rankingLabel = (r: Doc<DivisionRanking>) => {
  const p = parseRankingKey(r.id);
  return p ? labelFor(p.level, p.division) : r.id;
};
export const whole = (v: unknown) => (typeof v === "number" ? Math.round(v) : 0);
const updated = (at?: string | null) =>
  at ? ` Updated ${formatDateTime(at, { dateStyle: "medium", timeStyle: "short" })}.` : "";

/** What the server read for visitors: the keys with teams, and the chosen one's ranking. */
export interface VisitorRankings {
  keys: string[];
  current: PublicDivisionRanking | null;
}

/**
 * Team rankings by Level and Division (`?level=&division=`; the old
 * `?division=club-mixed` still works), or player ratings (`?kind=players`).
 * [visitor] is null when the API couldn't answer.
 */
export function Rankings({ kind, want, visitor }: { kind: "teams" | "players"; want: RankingWant; visitor: VisitorRankings | null }) {
  const teamsHref = want.level && want.division ? rankingsHref(want.level, want.division) : "/rankings";
  return (
    <div className="stack">
      <nav className="segmented" aria-label="Rankings">
        <Link href={teamsHref} className={kind === "teams" ? "on" : ""} aria-current={kind === "teams" ? "page" : undefined} replace scroll={false}>
          Teams
        </Link>
        <Link
          href="/rankings?kind=players"
          className={kind === "players" ? "on" : ""}
          aria-current={kind === "players" ? "page" : undefined}
          replace
          scroll={false}
        >
          Players
        </Link>
      </nav>
      {kind === "players" ? (
        <MembersOnly next="/rankings?kind=players" what="Sign up free or log in to see player ratings.">
          <Players />
        </MembersOnly>
      ) : (
        <TeamsForEveryone want={want} visitor={visitor} />
      )}
    </div>
  );
}

/** Live for members; the server's answer for visitors (and while sign-in is still loading). */
function TeamsForEveryone({ want, visitor }: { want: RankingWant; visitor: VisitorRankings | null }) {
  const { user } = useAuth();
  if (user) return <MemberTeams want={want} />;
  if (!visitor) {
    return user === null ? (
      <ErrorNote>Couldn&apos;t load the rankings. Try again in a minute.</ErrorNote>
    ) : (
      <p className="muted" aria-busy="true">
        Loading…
      </p>
    );
  }
  const choice = chooseRanking(visitor.keys, want);
  if (!choice || !visitor.current) return <NoRankings />;
  return <TeamRanking choice={choice} ranking={visitor.current} />;
}

function MemberTeams({ want }: { want: RankingWant }) {
  const { data, error } = useLiveQuery<DivisionRanking>("rankings", [], "rankings");
  if (error) return <ErrorNote>{error}</ErrorNote>;
  if (!data) return <p className="muted">Loading…</p>;
  const ranked = new Map(data.filter(isShownRanking).map((r) => [r.id, r] as const));
  const choice = chooseRanking(ranked.keys(), want);
  if (!choice) return <NoRankings />;
  const r = ranked.get(choice.key)!;
  return <TeamRanking choice={choice} ranking={{ teams: r.teams ?? [], minGames: r.minGames, updatedAt: r.updatedAt }} />;
}

function NoRankings() {
  return (
    <div className="card">
      <h2 className="card-title">No team rankings yet</h2>
      <p className="muted">Teams get ranked once they play 5 games in public tournaments hosted on Stall 10.</p>
    </div>
  );
}

/** The Level and Division filters: links, so they work before the page's script loads. */
function RankingFilters({ choice }: { choice: RankingChoice }) {
  return (
    <div className="rankings-filters">
      <FilterGroup<RankedLevel>
        label="Level"
        options={choice.levels}
        current={choice.level}
        text={(l) => rankedLevelLabels[l]}
        href={(l) => rankingsHref(l, choice.division)}
      />
      <FilterGroup<Division>
        label="Division"
        options={choice.divisions}
        current={choice.division}
        text={(d) => rankingDivisionLabels[d]}
        href={(d) => rankingsHref(choice.level, d)}
      />
    </div>
  );
}

function FilterGroup<T extends string>({
  label,
  options,
  current,
  text,
  href,
}: {
  label: string;
  options: T[];
  current: T;
  text: (v: T) => string;
  href: (v: T) => string;
}) {
  return (
    <div className="rankings-filter">
      <span className="rankings-filter-label">{label}</span>
      <nav className="segmented" aria-label={label}>
        {options.map((o) => (
          <Link key={o} href={href(o)} className={o === current ? "on" : ""} aria-current={o === current ? "true" : undefined} replace scroll={false}>
            {text(o)}
          </Link>
        ))}
      </nav>
    </div>
  );
}

function TeamRanking({
  choice,
  ranking,
}: {
  choice: RankingChoice;
  ranking: { teams: RankedTeam[]; minGames?: number; updatedAt?: string | null };
}) {
  return (
    <>
      <RankingFilters choice={choice} />
      <div className="card">
        <h2 className="card-title">{labelFor(choice.level, choice.division)}</h2>
        <table className="rankings-table">
          <thead>
            <tr>
              <th scope="col">#</th>
              <th scope="col">Team</th>
              <th scope="col">W–L</th>
              <th scope="col">Rating</th>
            </tr>
          </thead>
          <tbody>
            {ranking.teams.map((t) => (
              <tr key={t.teamId || t.rank}>
                <td>{whole(t.rank)}</td>
                <td>{t.teamId ? <Link href={`/teams/${encodeURIComponent(t.teamId)}`}>{t.name}</Link> : t.name}</td>
                <td>
                  {whole(t.wins)}–{whole(t.losses)}
                </td>
                <td>{whole(t.rating)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="muted small">
          Ratings come from the score of every game in public tournaments over the last 12 months: bigger wins and newer
          games count more, and beating strong teams counts more than beating weak ones. Teams need{" "}
          {ranking.minGames ?? 5} games to be ranked. Youth teams aren&apos;t ranked.{updated(ranking.updatedAt)}
        </p>
      </div>
    </>
  );
}

function Players() {
  const { data, error } = useLiveDoc<PlayerRanking>("playerRankings/all");
  if (error) return <ErrorNote>{error}</ErrorNote>;
  if (data === undefined) return <p className="muted">Loading…</p>;
  const players = data?.players ?? [];
  if (players.length === 0) {
    return (
      <div className="card">
        <h2 className="card-title">No player ratings yet</h2>
        <p className="muted">
          Players get rated once their team logs 10 of their games with the stat tracker. Only public profiles that show
          stats are rated.
        </p>
      </div>
    );
  }
  return (
    <div className="card">
      <h2 className="card-title">Players</h2>
      <table className="rankings-table">
        <thead>
          <tr>
            <th scope="col">#</th>
            <th scope="col">Player</th>
            <th scope="col">Games</th>
            <th scope="col">Rating</th>
          </tr>
        </thead>
        <tbody>
          {players.map((p) => (
            <tr key={p.uid || p.rank}>
              <td>{whole(p.rank)}</td>
              <td>
                <Link className="rankings-player" href={`/players/${encodeURIComponent(p.uid)}`}>
                  <Avatar name={p.name} url={p.photoUrl} size={28} />
                  <span>
                    {p.name}
                    {p.username && <small className="muted"> @{p.username}</small>}
                  </span>
                </Link>
              </td>
              <td>{whole(p.games)}</td>
              <td>{whole(p.rating)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="muted small">
        Ratings come from stats logged with the game tracker this season and last (last season counts half): goals,
        assists, blocks and touches per point played, less throwaways and drops. More points played means a steadier
        rating. 50 is average. Players need {data?.minGames ?? 10} games, and a public profile that shows stats. Players
        on youth teams aren&apos;t rated.
        {updated(data?.updatedAt)}
      </p>
    </div>
  );
}
