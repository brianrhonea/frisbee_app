"use client";
import { gameWon, ourScore, ranked, statSheetOfGames, type StatsGame, theirScore } from "@stall10/shared";
import Link from "next/link";
import { useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useAuth } from "../../AuthProvider";
import { useTeamHub } from "../TeamContext";
import {
  apiUrl,
  badge,
  dateTime,
  gameUrl,
  nameMap,
  shortDate,
  statsAccess,
  statsUrl,
  tournamentUrl,
  useLinkableEvents,
  useStatsGames,
  useStatsPlayers,
  useStatsTournaments,
} from "./data";
import { NewStatsForm } from "./NewStatsForm";
import "./stats.css";

/** One game row: opponent, date, score and result (GameRow). */
export function GameRow({ teamId, game, onDelete }: { teamId: string; game: StatsGame; onDelete?: () => void }) {
  const b = badge(game, gameWon(game));
  return (
    <li className="st-game-row">
      <Link href={gameUrl(teamId, game.id)} className="st-game-link">
        <span>
          <b>vs {game.opponent || "Opponent"}</b>
          <small className="muted">{dateTime(game.date)}</small>
        </span>
        <span className="st-score">
          {ourScore(game)}–{theirScore(game)}
        </span>
        <span className={`st-badge st-${b.tone}`}>{b.text}</span>
      </Link>
      {onDelete && (
        <button type="button" className="text-btn st-danger" onClick={onDelete} aria-label={`Delete the game vs ${game.opponent}`}>
          Delete
        </button>
      )}
    </li>
  );
}

/** Asks, then deletes; reports a failure (runDelete). */
export async function confirmAndDelete(
  user: Parameters<typeof callApi>[0],
  path: string,
  message: string,
  onError: (m: string) => void,
): Promise<boolean> {
  if (!window.confirm(message)) return false;
  try {
    await callApi(user, path, { method: "DELETE" });
    return true;
  } catch (e) {
    onError(problem(e, "Couldn't delete it. Try again."));
    return false;
  }
}

export const deleteGameMessage = (g: StatsGame) =>
  `Delete game vs ${g.opponent}?\n\nThis permanently deletes the game (${ourScore(g)}–${theirScore(g)}, ${shortDate(g.date)}) and every stat in it. Season and tournament totals will no longer count it.`;

/**
 * The Stats tab (StatsTab in the app): the season record and top +/-, the
 * tournament folders, standalone games, and for stats keepers new games
 * and tournaments.
 */
export function StatsHome() {
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const access = statsAccess(viewer);
  const games = useStatsGames(teamId);
  const tournaments = useStatsTournaments(teamId);
  const players = useStatsPlayers(teamId);
  const events = useLinkableEvents(access.keepStats ? teamId : null);
  const [adding, setAdding] = useState<"game" | "tournament" | null>(null);
  const [error, setError] = useState("");

  const failed = games.error ?? tournaments.error;
  if (failed) return <p className="form-error">{failed}</p>;
  if (!games.data || !tournaments.data) return <p className="muted" aria-busy="true">Loading…</p>;

  const all = games.data;
  const nameOf = nameMap(players.data);
  const wins = all.filter((g) => gameWon(g) === true).length;
  const losses = all.filter((g) => gameWon(g) === false).length;
  const leaders = ranked(statSheetOfGames(all)).slice(0, 3);
  const standalone = all.filter((g) => g.tournamentId === null);

  const del = async (path: string, message: string) => {
    if (!user) return;
    setError("");
    await confirmAndDelete(user, path, message, setError);
  };

  return (
    <div className="stack">
      <div className="home-actions">
        {access.keepStats && (
          <>
            <button type="button" className="btn btn-primary btn-small" onClick={() => setAdding("game")}>
              New game
            </button>
            <button type="button" className="btn btn-small" onClick={() => setAdding("tournament")}>
              New tournament
            </button>
          </>
        )}
        <Link href={statsUrl(teamId, "/players")} className="btn btn-small">
          Roster players
        </Link>
      </div>
      {adding && (
        <NewStatsForm
          key={adding}
          teamId={teamId}
          kind={adding}
          events={events(adding)}
          tournaments={tournaments.data}
          games={all}
          players={players.data ?? []}
          canCreateEvents={access.manageEvents}
          onClose={() => setAdding(null)}
        />
      )}
      {error && <p className="form-error">{error}</p>}

      <section className="card st-season">
        <div className="st-season-head">
          <div>
            <small className="muted">Season</small>
            <b className="st-record">
              {wins}–{losses}
            </b>
          </div>
          <Link href={statsUrl(teamId, "/season")} className="btn btn-small">
            Season stats
          </Link>
        </div>
        {leaders.length > 0 && (
          <>
            <h3 className="card-title">Top +/-</h3>
            <ol className="st-leaders">
              {leaders.map((p) => (
                <li key={p.playerId}>
                  <span>{nameOf(p.playerId)}</span>
                  <small className="muted">
                    {p.goals}G {p.assists}A {p.handBlocks + p.breakups}D
                  </small>
                  <b className="st-pos">+{p.plusMinus}</b>
                </li>
              ))}
            </ol>
          </>
        )}
      </section>

      <h3 className="section-title">Tournaments</h3>
      {tournaments.data.length === 0 ? (
        <p className="empty">No tournaments yet.</p>
      ) : (
        <ul className="game-list">
          {tournaments.data.map((t) => {
            const its = all.filter((g) => g.tournamentId === t.id);
            const w = its.filter((g) => gameWon(g) === true).length;
            const l = its.filter((g) => gameWon(g) === false).length;
            return (
              <li key={t.id} className="st-game-row">
                <Link href={tournamentUrl(teamId, t.id)} className="st-game-link">
                  <span>
                    <b>{t.name}</b>
                    <small className="muted">
                      {[shortDate(t.startDate), `${its.length} game${its.length === 1 ? "" : "s"}`, ...(w + l > 0 ? [`${w}–${l}`] : [])].join(" · ")}
                    </small>
                  </span>
                </Link>
                {access.canDelete && (
                  <button
                    type="button"
                    className="text-btn st-danger"
                    onClick={() =>
                      del(
                        apiUrl(teamId, `/stats-tournaments/${encodeURIComponent(t.id)}`),
                        `Delete ${t.name}?\n\nThis permanently deletes the tournament, its roster and lines, and ${its.length === 1 ? "its game" : `all ${its.length} of its games`} with every stat in them.`,
                      )
                    }
                  >
                    Delete
                  </button>
                )}
              </li>
            );
          })}
        </ul>
      )}

      <h3 className="section-title">Games</h3>
      {standalone.length === 0 ? (
        <p className="empty">No standalone games yet.</p>
      ) : (
        <ul className="game-list">
          {standalone.map((g) => (
            <GameRow
              key={g.id}
              teamId={teamId}
              game={g}
              onDelete={access.canDelete ? () => del(apiUrl(teamId, `/stats-games/${encodeURIComponent(g.id)}`), deleteGameMessage(g)) : undefined}
            />
          ))}
        </ul>
      )}
    </div>
  );
}
