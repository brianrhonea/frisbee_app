"use client";
// A hosted tournament's live state for its page, as the app's
// HostedTournamentViewModel keeps it: the tournament, its divisions,
// entries, host team and the viewer's teams, the selected division's
// games, and what the viewer may do. Reads are Firestore listeners (the
// rules decide what each viewer sees); writes go through the API.
import {
  type DivisionDoc,
  type EngineGame,
  type EntryDoc,
  type EntryStatus,
  engineGame,
  gamesToPlay,
  type GameDoc,
  type TournamentDoc,
} from "@stall10/shared";
import { orderBy, where } from "firebase/firestore";
import { useMemo, useState } from "react";
import { useAuth } from "@/components/AuthProvider";
import type { TeamDoc } from "@/components/team/TeamContext";
import { ApiError, callApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";

const editors = ["owner", "coach", "captain"];

/** can(team, perm) from the rules, for the viewer. */
export function canOn(team: TeamDoc | null | undefined, uid: string | undefined, perm: string): boolean {
  if (!team || !uid) return false;
  const tier = team.members?.[uid];
  if (tier && editors.includes(tier)) return true;
  return !!team.memberIds?.includes(uid) && ((team.memberPerms?.[uid] as string[] | undefined) ?? []).includes(perm);
}

export type MyTeam = Doc<TeamDoc & { division?: string; level?: string }>;

export function useTournament(id: string) {
  const { user } = useAuth();
  const uid = user?.uid;
  const live = useLiveDoc<TournamentDoc>(user ? `tournaments/${id}` : null);
  const t = live.data ?? null;
  const host = useLiveDoc<TeamDoc>(user && t?.hostId ? `teams/${t.hostId}` : null);
  const divRows = useLiveQuery<DivisionDoc>(user && t ? `tournaments/${id}/divisions` : null, [], id);
  const entryRows = useLiveQuery<EntryDoc>(user && t ? `tournaments/${id}/entries` : null, [], id);
  const mine = useLiveQuery<TeamDoc & { division?: string; level?: string }>(
    uid ? "teams" : null,
    uid ? [where("memberIds", "array-contains", uid)] : [],
    uid ?? "",
  );
  const manager = canOn(host.data, uid, "manageEvents");

  // In the tournament's order.
  const divisions = useMemo(() => {
    const byId = new Map((divRows.data ?? []).map((d) => [d.id, d]));
    return (t?.divisions ?? []).map((s) => byId.get(s.id)).filter((d): d is Doc<DivisionDoc> => !!d);
  }, [divRows.data, t?.divisions]);
  const entries = useMemo(() => [...(entryRows.data ?? [])].sort((a, b) => a.teamName.localeCompare(b.teamName)), [entryRows.data]);
  const myTeams = mine.data ?? [];

  // The viewer's division until they pick another, else the first.
  const [picked, setPicked] = useState<string | null>(null);
  const myTeamIds = useMemo(() => {
    const ids = new Set<string>();
    for (const d of divisions) for (const x of d.teams ?? []) if (uid && x.playerIds.includes(uid)) ids.add(x.id);
    for (const e of entries) if (e.status === "accepted" && myTeams.some((m) => m.id === e.id)) ids.add(e.id);
    return ids;
  }, [divisions, entries, myTeams, uid]);
  const myDivisionId = divisions.find((d) => d.seeds.some((s) => myTeamIds.has(s)) || (d.teams ?? []).some((x) => myTeamIds.has(x.id)))?.id ?? null;
  const divisionId = (picked && divisions.some((d) => d.id === picked) ? picked : null) ?? myDivisionId ?? divisions[0]?.id ?? null;
  const division = divisions.find((d) => d.id === divisionId) ?? null;

  const gameRows = useLiveQuery<GameDoc>(user && divisionId ? `tournaments/${id}/divisions/${divisionId}/games` : null, [orderBy("order")], `${divisionId}`);
  const games: EngineGame[] = useMemo(() => (gameRows.data ?? []).map((g) => engineGame(g.id, g)), [gameRows.data]);

  const entryOf = (teamId: string) => entries.find((e) => e.id === teamId) ?? null;
  const teamName = (teamId: string | null | undefined): string => {
    if (!teamId) return "TBD";
    const e = entryOf(teamId);
    if (e) return e.teamName;
    for (const d of divisions) {
      const drafted = (d.teams ?? []).find((x) => x.id === teamId);
      if (drafted) return drafted.name;
    }
    return "Team";
  };
  const myAdminTeams = myTeams.filter((m) => (m.kind ?? "team") === "team" && canOn(m, uid, "manageTeam"));
  const myEntries = entries.filter((e) => myAdminTeams.some((m) => m.id === e.id));
  /** Teams of the selected division whose captain the viewer is. */
  const captainOf = new Set(Object.entries(division?.captains ?? {}).filter(([, l]) => uid && l.includes(uid)).map(([k]) => k));

  return {
    id,
    uid,
    user,
    loaded: live.data !== undefined || !!live.error,
    error: live.error,
    t,
    manager,
    host: host.data ?? null,
    divisions,
    division,
    divisionId,
    selectDivision: setPicked,
    entries,
    entryOf,
    entriesIn: (div: string, status?: EntryStatus) => entries.filter((e) => e.divisionId === div && (!status || e.status === status)),
    entriesWith: (status: EntryStatus) => entries.filter((e) => e.status === status),
    myTeams,
    myAdminTeams,
    myEntries,
    myTeamIds,
    myDivisionId,
    /** Admin teams that haven't entered yet (or withdrew). */
    teamsToEnter: myAdminTeams.filter((m) => !entries.some((e) => e.id === m.id && e.status !== "withdrawn")),
    /** The viewer's team that's entered here, if any. */
    myActiveEntry: entries.find((e) => myTeams.some((m) => m.id === e.id) && ["applied", "accepted", "waitlisted"].includes(e.status)) ?? null,
    games,
    gamesLoaded: gameRows.data !== undefined,
    published: games.length > 0,
    teamName,
    captainOf,
    myUpcoming: gamesToPlay(games).filter((g) => captainOf.has(g.teamA ?? "") || captainOf.has(g.teamB ?? "")),
  };
}

export type TournamentState = ReturnType<typeof useTournament>;

/** Calls the API with a busy flag and the error to show. */
export function useAction() {
  const { user } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function run<T = void>(path: string, method: string, body?: unknown): Promise<{ ok: true; value: T } | { ok: false }> {
    if (!user) return { ok: false };
    setBusy(true);
    setError(null);
    try {
      return { ok: true, value: await callApi<T>(user, path, { method, body }) };
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Something went wrong. Try again.");
      return { ok: false };
    } finally {
      setBusy(false);
    }
  }
  return { busy, error, setError, run };
}

export const tournamentPath = (id: string) => `/v1/tournaments/${encodeURIComponent(id)}`;
export const divisionPath = (id: string, div: string) => `${tournamentPath(id)}/divisions/${encodeURIComponent(div)}`;
