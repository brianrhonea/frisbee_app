"use client";
// The member's teams on a tournament day (TournamentDays in the app): for
// each team's accepted entry from the day before the event to its last day,
// the tournament, its entries (division and names), the division
// (captains) and its games, live; tournamentDay (packages/shared) decides
// what the card shows.
import {
  type DivisionDoc,
  type EngineGame,
  type EnteredTournamentDoc,
  type EntryDoc,
  engineGame,
  type GameDoc,
  type HostedStatus,
  type TournamentDay,
  type TournamentDoc,
  tournamentDay,
} from "@stall10/shared";
import { collection, doc, onSnapshot, orderBy, query } from "firebase/firestore";
import { useEffect, useMemo, useState } from "react";
import { firestoreDb } from "@/lib/firebase";
import { plain } from "@/lib/live";
import type { TeamDoc } from "../team/TeamContext";
import { useMyTeams } from "../useMyTeams";

/** One team's card (TeamTournamentDay in the app). */
export interface TeamTournamentDay {
  teamId: string;
  teamName: string;
  tournamentId: string;
  tournamentName: string;
  status: HostedStatus;
  divisionId: string;
  day: TournamentDay;
  /** Entered teams' names by id. */
  names: Record<string, string>;
  /** The viewer captains this team here: they report its scores. */
  isCaptain: boolean;
}

export const nameOf = (d: TeamTournamentDay, teamId: string | null | undefined) => (teamId ? (d.names[teamId] ?? "TBD") : "TBD");

/** The game a captain should act on now (report or confirm), if any. */
export const actionGame = (d: TeamTournamentDay): EngineGame | null =>
  d.isCaptain && (d.day.scoreDueKind === "report" || d.day.scoreDueKind === "confirm") ? d.day.scoreDue : null;

const day = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

/** Accepted entries from the day before they start to the day they end. */
function current(e: EnteredTournamentDoc, now: Date): boolean {
  if (e.status !== "accepted" || !e.startsOn) return false;
  const starts = new Date(e.startsOn);
  const from = new Date(starts.getFullYear(), starts.getMonth(), starts.getDate() - 1).getTime();
  const to = day(e.endsOn ? new Date(e.endsOn) : starts);
  const today = day(now);
  return today >= from && today <= to;
}

interface Follow {
  t?: TournamentDoc;
  entries?: Array<EntryDoc & { id: string }>;
  divisions?: Array<DivisionDoc & { id: string }>;
  games?: EngineGame[];
}

/**
 * [uid]'s teams' tournament days, today's first; only [teamId]'s when it's
 * given (the team page). Re-checked each minute while something is on.
 */
export function useTournamentDays(uid: string | null | undefined, teamId?: string): TeamTournamentDay[] {
  const mine = useMyTeams<TeamDoc>(uid);
  const teams = useMemo(
    () => (mine.data ?? []).filter((t) => (t.kind ?? "team") === "team" && (!teamId || t.id === teamId)),
    [mine.data, teamId],
  );
  const teamKey = teams.map((t) => t.id).join(",");
  const [entered, setEntered] = useState<Record<string, Array<EnteredTournamentDoc & { id: string }>>>({});
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const db = firestoreDb();
    if (!db || !uid || !teamKey) return;
    const stops = teamKey.split(",").map((t) =>
      onSnapshot(
        collection(db, `teams/${t}/tournamentEntries`),
        (snap) => setEntered((m) => ({ ...m, [t]: snap.docs.map((d) => ({ ...(plain(d.data()) as EnteredTournamentDoc), id: d.id })) })),
        () => setEntered((m) => ({ ...m, [t]: [] })),
      ),
    );
    return () => stops.forEach((s) => s());
  }, [uid, teamKey]);

  // "teamId/tournamentId" for each entry on now.
  const keys = teamKey
    ? teamKey
        .split(",")
        .flatMap((t) => (entered[t] ?? []).filter((e) => current(e, now)).map((e) => `${t}/${e.id}`))
        .sort()
        .join("|")
    : "";

  useEffect(() => {
    if (!keys) return;
    const tick = setInterval(() => setNow(new Date()), 60_000);
    return () => clearInterval(tick);
  }, [keys]);

  const [follows, setFollows] = useState<Record<string, Follow>>({});
  useEffect(() => {
    const db = firestoreDb();
    setFollows({});
    if (!db || !keys) return;
    const stops: Array<() => void> = [];
    const set = (key: string, part: Follow) => setFollows((m) => ({ ...m, [key]: { ...m[key], ...part } }));
    for (const key of keys.split("|")) {
      const [team, tid] = key.split("/");
      const base = `tournaments/${tid}`;
      stops.push(onSnapshot(doc(db, base), (s) => set(key, { t: s.exists() ? (plain(s.data()) as TournamentDoc) : undefined }), () => {}));
      stops.push(
        onSnapshot(
          collection(db, `${base}/divisions`),
          (s) => set(key, { divisions: s.docs.map((d) => ({ ...(plain(d.data()) as DivisionDoc), id: d.id })) }),
          () => {},
        ),
      );
      let gamesOf: string | null = null;
      let stopGames: (() => void) | null = null;
      stops.push(() => stopGames?.());
      stops.push(
        onSnapshot(
          collection(db, `${base}/entries`),
          (s) => {
            const entries = s.docs.map((d) => ({ ...(plain(d.data()) as EntryDoc), id: d.id }));
            set(key, { entries });
            const division = entries.find((e) => e.id === team)?.divisionId ?? null;
            if (division === gamesOf) return;
            gamesOf = division;
            stopGames?.();
            stopGames = null;
            set(key, { games: [] });
            if (!division) return;
            stopGames = onSnapshot(
              query(collection(db, `${base}/divisions/${division}/games`), orderBy("order")),
              (g) => set(key, { games: g.docs.map((d) => engineGame(d.id, plain(d.data()) as GameDoc)) }),
              () => {},
            );
          },
          () => {},
        ),
      );
    }
    return () => stops.forEach((s) => s());
  }, [keys]);

  return useMemo(() => {
    const out: TeamTournamentDay[] = [];
    for (const [key, f] of Object.entries(follows)) {
      const [team, tid] = key.split("/");
      const entry = f.entries?.find((e) => e.id === team);
      const t = f.t;
      if (!t || !entry || !["scheduled", "live", "finished"].includes(t.status)) continue;
      const d = tournamentDay(f.games ?? [], team, now, t.status === "live");
      if (!d) continue;
      const division = f.divisions?.find((x) => x.id === entry.divisionId);
      out.push({
        teamId: team,
        teamName: teams.find((x) => x.id === team)?.name ?? entry.teamName,
        tournamentId: tid,
        tournamentName: t.name,
        status: t.status,
        divisionId: entry.divisionId,
        day: d,
        names: Object.fromEntries((f.entries ?? []).map((e) => [e.id, e.teamName])),
        isCaptain: !!uid && (division?.captains?.[team] ?? []).includes(uid),
      });
    }
    const far = Number.MAX_SAFE_INTEGER;
    return out.sort((a, b) =>
      a.day.phase !== b.day.phase
        ? a.day.phase === "today"
          ? -1
          : 1
        : (a.day.next?.game.startsAt?.getTime() ?? far) - (b.day.next?.game.startsAt?.getTime() ?? far),
    );
  }, [follows, now, teams, uid]);
}
