"use client";
// Live reads for the stats pages, as the app's StatsRepository watches them
// (statsGames by date, statsTournaments by startDate, the roster), and who
// may do what, as the app's view models decide it.
import {
  rosterMax,
  sortPlayers,
  type StatsGame,
  type StatsPlayer,
  type StatsTournament,
  statsGameFrom,
  statsPlayerFrom,
  statsTournamentFrom,
} from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import { useMemo } from "react";
import { useLiveQuery } from "@/lib/live";
import type { TeamViewer } from "../TeamContext";
import { formatDate, formatDateTime } from "@/lib/dates";

type Member = Extract<TeamViewer, { state: "member" }>;

// Bounded reads, well past any real team's: season totals and the game
// and tournament pages add up everything read, so these must never cut a
// real list short (the roster is capped at rosterMax by the API).
const statsGamesCap = 2000;
const statsTournamentsCap = 500;
const editors = ["owner", "coach", "captain"];

/**
 * Team.has in the app (and canKeepStats in the rules): editors have every
 * permission; others need keepStats from a role, the statKeepers list, or
 * the legacy "stats" tier.
 */
export function statsAccess(viewer: TeamViewer) {
  if (viewer.state !== "member") return { member: false, keepStats: false, canDelete: false, manageTeam: false, manageEvents: false, uid: "" };
  const v: Member = viewer;
  const editor = editors.includes(v.tier);
  const perms = v.team.memberPerms?.[v.uid] ?? [];
  const keepStats = editor || perms.includes("keepStats") || (v.team.statKeepers ?? []).includes(v.uid) || v.tier === "stats";
  const manageTeam = editor || perms.includes("manageTeam");
  return {
    member: true,
    uid: v.uid,
    keepStats,
    /** Deleting games and tournaments: admins who keep stats (StatsViewModel.canDelete). */
    canDelete: keepStats && manageTeam,
    /** The roster and the paid marks (TeamDetailViewModel.canEdit). */
    manageTeam,
    manageEvents: editor || perms.includes("manageEvents"),
  };
}

export function useStatsGames(teamId: string | null) {
  const live = useLiveQuery(teamId ? `teams/${teamId}/statsGames` : null, [orderBy("date", "desc"), limit(statsGamesCap)], "statsGames");
  const data = useMemo(() => live.data?.map((d) => statsGameFrom(d.id, d)), [live.data]);
  return { data, error: live.error };
}

export function useStatsTournaments(teamId: string | null) {
  const live = useLiveQuery(teamId ? `teams/${teamId}/statsTournaments` : null, [orderBy("startDate", "desc"), limit(statsTournamentsCap)], "statsTournaments");
  const data = useMemo(() => live.data?.map((d) => statsTournamentFrom(d.id, d)), [live.data]);
  return { data, error: live.error };
}

/** The roster, by number then name; with the paid marks for admins (rosterStatus is theirs only). */
export function useStatsPlayers(teamId: string | null, withStatus = false) {
  const roster = useLiveQuery(teamId ? `teams/${teamId}/roster` : null, [limit(rosterMax)], "roster");
  const status = useLiveQuery<{ paid?: boolean }>(teamId && withStatus ? `teams/${teamId}/rosterStatus` : null, [limit(rosterMax)], "rosterStatus");
  const data = useMemo(() => {
    if (!roster.data) return undefined;
    const paid = new Map((status.data ?? []).map((s) => [s.id, s]));
    return sortPlayers(roster.data.map((d) => statsPlayerFrom(d.id, d, paid.get(d.id))));
  }, [roster.data, status.data]);
  return { data, error: roster.error };
}

export interface LinkableEvent {
  id: string;
  title: string;
  type: string;
  startsAt: string;
  location: string;
}

/**
 * Schedule events a tournament (tournament events) or a game (anything
 * but social and workout) can link to, closest to now first
 * (StatsViewModel.linkableEvents).
 */
export function useLinkableEvents(teamId: string | null) {
  const live = useLiveQuery<{ title?: string; type?: string; startsAt?: string; location?: string }>(
    teamId ? `teams/${teamId}/events` : null,
    [orderBy("startsAt", "desc"), limit(300)],
    "statsEvents",
  );
  return useMemo(() => {
    const events: LinkableEvent[] = (live.data ?? []).map((e) => ({
      id: e.id,
      title: e.title || "Event",
      type: e.type || "other",
      startsAt: e.startsAt || new Date().toISOString(),
      location: e.location || "",
    }));
    return (kind: "tournament" | "game") => {
      const now = Date.now();
      return events
        .filter((e) => (kind === "tournament" ? e.type === "tournament" : e.type !== "social" && e.type !== "workout"))
        .sort((a, b) => Math.abs(Date.parse(a.startsAt) - now) - Math.abs(Date.parse(b.startsAt) - now));
    };
  }, [live.data]);
}

export const statsUrl = (teamId: string, rest = "") => `/teams/${encodeURIComponent(teamId)}/stats${rest}`;
export const apiUrl = (teamId: string, rest: string) => `/v1/teams/${encodeURIComponent(teamId)}${rest}`;
export const gameUrl = (teamId: string, id: string) => statsUrl(teamId, `/games/${encodeURIComponent(id)}`);
export const tournamentUrl = (teamId: string, id: string) => statsUrl(teamId, `/tournaments/${encodeURIComponent(id)}`);

export function nameMap(players: StatsPlayer[] | undefined) {
  const m = new Map((players ?? []).map((p) => [p.id, p.name]));
  return (id: string) => m.get(id) ?? "Player";
}

/** "W", "L", "T" or "LIVE" for a game row (GameRow). */
export function badge(g: StatsGame, won: boolean | null): { text: string; tone: "win" | "loss" | "live" } {
  if (won === true) return { text: "W", tone: "win" };
  if (won === false) return { text: "L", tone: "loss" };
  return { text: g.finished ? "T" : "LIVE", tone: "live" };
}

export const shortDate = (iso: string) => formatDate(iso, { month: "short", day: "numeric" });
export const dateTime = (iso: string) =>
  formatDateTime(iso, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });

export type { StatsGame, StatsTournament, StatsPlayer };
