"use client";
// A team's tournament day (TournamentDayCard in the app), on the member
// home page and the team page in place of the next event: its next game,
// record, pool place and last result, and Report score for its captains,
// which opens that game on the tournament page.
import { ordinal } from "@stall10/shared";
import Link from "next/link";
import { useRenderZone } from "@/lib/renderZone";
import { actionGame, nameOf, type TeamTournamentDay } from "./useTournamentDays";
import "./tournament_day.css";

/** /tournaments/{id}, opened on [game] (in [division]) or a [tab]. */
export function tournamentHref(id: string, o: { division?: string; game?: string; tab?: string } = {}): string {
  const q = new URLSearchParams();
  if (o.division) q.set("division", o.division);
  if (o.game) q.set("game", o.game);
  if (o.tab) q.set("tab", o.tab);
  const s = q.toString();
  return `/tournaments/${encodeURIComponent(id)}${s ? `?${s}` : ""}`;
}

export function TournamentDayCard({ day: d, showTeam = true }: { day: TeamTournamentDay; showTeam?: boolean }) {
  const zone = useRenderZone();
  const time = (at: Date) => at.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", timeZone: zone });
  // "8:30 AM" today, "Tomorrow 8:30 AM", else "Sat 8:30 AM".
  const when = (at: Date) => {
    const days = Math.round((Date.UTC(at.getFullYear(), at.getMonth(), at.getDate()) - Date.UTC(d.now.getFullYear(), d.now.getMonth(), d.now.getDate())) / 86_400_000);
    if (days === 0) return time(at);
    if (days === 1) return `Tomorrow ${time(at)}`;
    return `${at.toLocaleDateString("en-US", { weekday: "short", timeZone: zone })} ${time(at)}`;
  };
  const { last } = d.day;
  // The game being played, with its running score from this team's side
  // (in place of the next game: an earlier one may still need a score).
  const playing = d.liveGame;
  const live = playing ? d.live : null;
  const mineA = playing?.teamA === d.teamId;
  const next = playing ? { game: playing, opponent: (mineA ? playing.teamB : playing.teamA) ?? null } : d.day.next;
  const label = d.day.phase === "tomorrow" ? "Tomorrow" : d.status === "live" || live ? "Live" : "Today";
  const record = [
    d.day.wins + d.day.losses > 0 ? `${d.day.wins}–${d.day.losses}` : null,
    d.day.poolPlace != null ? `${ordinal(d.day.poolPlace)} in Pool ${d.day.pool}` : null,
  ]
    .filter(Boolean)
    .join(" · ");
  const action = actionGame(d);
  const schedule = tournamentHref(d.tournamentId, { division: d.divisionId, tab: "schedule" });
  return (
    <section className="card tournament-day" aria-label={`${d.tournamentName}: ${label.toLowerCase()}`}>
      <small className="tournament-day-when">
        {label === "Live" && <span className="tournament-day-dot" aria-hidden />}
        {[label, showTeam ? d.teamName : null].filter(Boolean).join(" · ")}
      </small>
      <Link className="tournament-day-name" href={schedule}>
        {d.tournamentName}
      </Link>
      {next ? (
        <div>
          {live ? (
            <small className="tournament-day-live">
              <span className="tournament-day-dot" aria-hidden />
              LIVE NOW
            </small>
          ) : (
            <small className="muted">{d.day.phase === "tomorrow" ? "First game" : "Next game"}</small>
          )}
          <span className="tournament-day-headline">
            <b className="tournament-day-vs">{next.opponent ? `vs ${nameOf(d, next.opponent)}` : next.game.label}</b>
            {live && (
              <b className="tournament-day-score" aria-label={`${mineA ? live.scoreA : live.scoreB} to ${mineA ? live.scoreB : live.scoreA}`}>
                {mineA ? live.scoreA : live.scoreB}–{mineA ? live.scoreB : live.scoreA}
              </b>
            )}
          </span>
          <span className="small">
            {[
              next.game.startsAt ? when(next.game.startsAt) : null,
              `Field ${next.game.field}`,
              next.opponent ? null : "opponent to be decided",
            ]
              .filter(Boolean)
              .join(" · ")}
          </span>
        </div>
      ) : d.day.awaiting ? (
        <div>
          <b className="tournament-day-vs">Next game to be decided</b>
          <span className="small">Waiting on the bracket</span>
        </div>
      ) : (
        <b className="tournament-day-vs">All games played</b>
      )}
      {(record || last) && (
        <p className="tournament-day-record small">
          {record && <b>{record}</b>}
          {last && (
            <span className="muted">
              Last: {last.won ? "W" : "L"} {last.scoreFor}–{last.scoreAgainst} vs {nameOf(d, last.opponent)}
            </span>
          )}
        </p>
      )}
      {d.isCaptain && d.day.scoreDueKind === "awaiting" && <p className="muted small">Waiting for the other captain to confirm your score.</p>}
      <div className="home-actions">
        {action && (
          <Link className="btn btn-small tournament-day-due" href={tournamentHref(d.tournamentId, { division: d.divisionId, game: action.id })}>
            {d.day.scoreDueKind === "confirm" ? "Confirm score" : "Report score"}
          </Link>
        )}
        <Link className="btn btn-small" href={schedule}>
          Schedule &amp; standings
        </Link>
      </div>
    </section>
  );
}
