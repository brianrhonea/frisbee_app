"use client";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useLiveDoc, useLiveQuery } from "@/lib/live";
import { Avatar } from "./Avatar";

// Stall 10's own rankings (the `rankings` Cloud Functions, nightly), as the
// app's Rankings screen shows them: rankings/{level-division} for teams and
// playerRankings/all for players. firestore.rules lets members read them.

interface RankedTeam {
  rank: number;
  teamId: string;
  name: string;
  rating: number;
  wins: number;
  losses: number;
}
interface DivisionRanking {
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
interface PlayerRanking {
  players?: RankedPlayer[];
  minGames?: number;
  updatedAt?: string;
}

const levels = ["club", "college", "youth", "league", "pickup"];
const divisions = ["mixed", "open", "women", "masters"];
const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const label = (r: DivisionRanking) => `${cap(r.level ?? "club")} ${cap(r.division ?? "mixed")}`;
const order = (r: DivisionRanking) => levels.indexOf(r.level ?? "") * 10 + divisions.indexOf(r.division ?? "");
const n = (v: unknown) => (typeof v === "number" ? Math.round(v) : 0);
const updated = (at?: string) =>
  at ? ` Updated ${new Date(at).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })}.` : "";

/** Team rankings by division, or player ratings (`?kind=players`). */
export function Rankings() {
  const params = useSearchParams();
  const router = useRouter();
  const kind = params.get("kind") === "players" ? "players" : "teams";
  const choose = (k: string) => router.replace(k === "players" ? "/rankings?kind=players" : "/rankings");

  return (
    <div className="stack">
      <div className="segmented" role="tablist" aria-label="Rankings">
        {(["teams", "players"] as const).map((k) => (
          <button key={k} type="button" role="tab" aria-selected={kind === k} className={kind === k ? "on" : ""} onClick={() => choose(k)}>
            {cap(k)}
          </button>
        ))}
      </div>
      {kind === "players" ? <Players /> : <Teams />}
    </div>
  );
}

function Teams() {
  const params = useSearchParams();
  const router = useRouter();
  const { data, error } = useLiveQuery<DivisionRanking>("rankings", [], "rankings");
  if (error) return <p className="form-error">{error}</p>;
  if (!data) return <p className="muted">Loading…</p>;
  const ranked = data.filter((r) => (r.teams?.length ?? 0) > 0).sort((a, b) => order(a) - order(b));
  if (ranked.length === 0) {
    return (
      <div className="card">
        <h2 className="card-title">No team rankings yet</h2>
        <p className="muted">Teams get ranked once they play 5 games in public tournaments hosted on Stall 10.</p>
      </div>
    );
  }
  const current = ranked.find((r) => r.id === params.get("division")) ?? ranked[0]!;
  return (
    <>
      <label className="rankings-pick">
        Division{" "}
        <select value={current.id} onChange={(e) => router.replace(`/rankings?division=${encodeURIComponent(e.target.value)}`)}>
          {ranked.map((r) => (
            <option key={r.id} value={r.id}>
              {label(r)}
            </option>
          ))}
        </select>
      </label>
      <div className="card">
        <h2 className="card-title">{label(current)}</h2>
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
            {(current.teams ?? []).map((t) => (
              <tr key={t.teamId || t.rank}>
                <td>{n(t.rank)}</td>
                <td>{t.teamId ? <Link href={`/teams/${encodeURIComponent(t.teamId)}`}>{t.name}</Link> : t.name}</td>
                <td>
                  {n(t.wins)}–{n(t.losses)}
                </td>
                <td>{n(t.rating)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <p className="muted small">
          Ratings come from the score of every game in public tournaments over the last 12 months: bigger wins and newer
          games count more, and beating strong teams counts more than beating weak ones. Teams need{" "}
          {current.minGames ?? 5} games to be ranked.{updated(current.updatedAt)}
        </p>
      </div>
    </>
  );
}

function Players() {
  const { data, error } = useLiveDoc<PlayerRanking>("playerRankings/all");
  if (error) return <p className="form-error">{error}</p>;
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
              <td>{n(p.rank)}</td>
              <td>
                <Link className="rankings-player" href={`/players/${encodeURIComponent(p.uid)}`}>
                  <Avatar name={p.name} url={p.photoUrl} size={28} />
                  <span>
                    {p.name}
                    {p.username && <small className="muted"> @{p.username}</small>}
                  </span>
                </Link>
              </td>
              <td>{n(p.games)}</td>
              <td>{n(p.rating)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="muted small">
        Ratings come from stats logged with the game tracker this season and last (last season counts half): goals,
        assists, blocks and touches per point played, less throwaways and drops. More points played means a steadier
        rating. 50 is average. Players need {data?.minGames ?? 10} games, and a public profile that shows stats.
        {updated(data?.updatedAt)}
      </p>
    </div>
  );
}
