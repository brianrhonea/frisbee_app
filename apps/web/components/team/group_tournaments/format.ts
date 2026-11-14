// Dates and names for group tournaments, in the viewer's own time zone
// (tournament_widgets.dart's helpers). Only rendered in the browser:
// tournaments come from live reads.
import {
  type GroupGame,
  type GroupTournamentDoc,
  type GroupTournamentSettings,
  type GroupTournamentTeam,
  groupSettingsSummary,
  groupTournamentFormatInfo,
  readGroupSettings,
  readGroupTeams,
} from "@stall10/shared";

const fmt = (iso: string, o: Intl.DateTimeFormatOptions) => new Date(iso).toLocaleString("en-US", o);

/** "Sat, Nov 7 · 9:00 AM". */
export const tournamentWhen = (iso: string) =>
  `${fmt(iso, { weekday: "short", month: "short", day: "numeric" })} · ${fmt(iso, { hour: "numeric", minute: "2-digit" })}`;

/** "9:00 AM". */
export const gameTime = (iso: string | null | undefined) => (iso ? fmt(iso, { hour: "numeric", minute: "2-digit" }) : "");

/** "Saturday, Nov 7", a heading for a day of games. */
export const gameDay = (iso: string) => fmt(iso, { weekday: "long", month: "short", day: "numeric" });

/** "Sat, Nov 7". */
export const shortDay = (iso: string) => fmt(iso, { weekday: "short", month: "short", day: "numeric" });

/** "Sat, Nov 7", or "Sat, Nov 7 – Sun, Nov 8 (2 days)". */
export function tournamentDates(s: GroupTournamentSettings) {
  const days = [s.startsAt, ...s.laterDays];
  return s.laterDays.length === 0 ? shortDay(s.startsAt) : `${shortDay(s.startsAt)} – ${shortDay(days[days.length - 1]!)} (${days.length} days)`;
}

export const sameDay = (a: string | null | undefined, b: string | null | undefined) =>
  !!a && !!b && new Date(a).toDateString() === new Date(b).toDateString();

/** "Pool play + single elimination · 5v5 · to 11 · ...". */
export const tournamentSummary = (s: GroupTournamentSettings) => `${groupTournamentFormatInfo[s.format].label} · ${groupSettingsSummary(s)}`;

/** A tournament doc with its defaults filled in (GroupTournament.fromMap). */
export interface GroupTournamentView {
  id: string;
  name: string;
  eventId: string | null;
  settings: GroupTournamentSettings;
  status: "setup" | "scheduled" | "done";
  teams: GroupTournamentTeam[];
}

export function tournamentView(d: GroupTournamentDoc & { id: string }): GroupTournamentView {
  return {
    id: d.id,
    name: d.name ?? "",
    eventId: typeof d.eventId === "string" ? d.eventId : null,
    settings: readGroupSettings(d.settings),
    status: d.status === "scheduled" || d.status === "done" ? d.status : "setup",
    teams: readGroupTeams(d.teams),
  };
}

export const teamName = (t: GroupTournamentView | null, id: string | null) => t?.teams.find((x) => x.id === id)?.name ?? "TBD";
export const playerName = (team: GroupTournamentTeam, uid: string) => team.playerNames[uid] ?? "Player";

/** "Winner of game 5", "Pool A #1" or the team's name. */
export function slotLabel(names: Map<string, string>, games: GroupGame[], g: GroupGame, a: boolean) {
  const team = a ? g.teamA : g.teamB;
  if (team !== null) return names.get(team) ?? "TBD";
  const s = a ? g.sourceA : g.sourceB;
  const number = (id: string) => {
    const x = games.find((y) => y.id === id);
    return x ? `${x.order + 1}` : "?";
  };
  if (!s) return "TBD";
  if (s.type === "pool") return `Pool ${s.pool} #${s.rank}`;
  return `${s.type === "winner" ? "Winner" : "Loser"} of game ${number(s.game)}`;
}
