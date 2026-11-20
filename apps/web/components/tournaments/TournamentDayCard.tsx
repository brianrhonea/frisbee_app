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
  const { next, last } = d.day;
  const when = d.day.phase === "tomorrow" ? "Tomorrow" : d.status === "live" ? "Live" : "Today";
  const record = [
    d.day.wins + d.day.losses > 0 ? `${d.day.wins}–${d.day.losses}` : null,
    d.day.poolPlace != null ? `${ordinal(d.day.poolPlace)} in Pool ${d.day.pool}` : null,
  ]
    .filter(Boolean)
    .join(" · ");
  const action = actionGame(d);
  const schedule = tournamentHref(d.tournamentId, { division: d.divisionId, tab: "schedule" });
  return (
    <section className="card tournament-day" aria-label={`${d.tournamentName}: ${when.toLowerCase()}`}>
      <small className="tournament-day-when">
        {when === "Live" && <span className="tournament-day-dot" aria-hidden />}
        {[when, showTeam ? d.teamName : null].filter(Boolean).join(" · ")}
      </small>
      <Link className="tournament-day-name" href={schedule}>
        {d.tournamentName}
      </Link>
      {next ? (
        <div>
          <small className="muted">{d.day.phase === "tomorrow" ? "First game" : "Next game"}</small>
          <b className="tournament-day-vs">{next.opponent ? `vs ${nameOf(d, next.opponent)}` : next.game.label}</b>
          <span className="small">
            {[
              next.game.startsAt ? `${d.day.phase === "tomorrow" ? "Tomorrow " : ""}${time(next.game.startsAt)}` : null,
              `Field ${next.game.field}`,
              next.opponent ? null : "opponent to be decided",
            ]
              .filter(Boolean)
              .join(" · ")}
          </span>
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
          <Link className="btn btn-primary btn-small" href={tournamentHref(d.tournamentId, { division: d.divisionId, game: action.id })}>
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
