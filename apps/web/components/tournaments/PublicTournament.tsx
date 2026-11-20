"use client";
// Hosted tournaments and leagues for signed-out visitors: the list and an
// event's page, server-rendered from the API's `/v1/public/tournaments*`
// (so search engines see them), read-only, with a sign-up prompt in place
// of entering, signing up and following. Members get the live pages as
// before once signed in. Sub-pages (signups, drafts, editing, hosting)
// stay members-only.
import {
  type DivisionDoc,
  type EngineGame,
  engineGame,
  type EntryDoc,
  type PublicHostedCard,
  type PublicHostedPage,
  type PublicTeamPost,
  type TournamentDoc,
} from "@stall10/shared";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo } from "react";
import { useAuth } from "@/components/AuthProvider";
import type { Doc } from "@/lib/live";
import { FindTournaments, TournamentFinder } from "./TournamentLists";
import { TournamentPage, TournamentView } from "./TournamentPage";
import type { TournamentState } from "./useTournament";
import { noLiveControls, serverLive } from "./useLiveScores";
import { JoinToTakePart } from "./VisitorParts";
import "./tournaments.css";

/** Visitors' live events reread the page this often, so scores keep up. */
const liveRefreshMs = 60_000;

/** Find tournaments: live for members, the server's list for visitors (and while sign-in is still loading). */
export function TournamentsForEveryone({ list }: { list: PublicHostedCard[] | null }) {
  const { user } = useAuth();
  if (user) return <FindTournaments />;
  if (!list) {
    return user === null ? <p className="form-error">Couldn&apos;t load events. Try again in a minute.</p> : <p className="muted" aria-busy="true">Loading…</p>;
  }
  return (
    <div className="stack">
      <JoinToTakePart next="/tournaments" />
      <TournamentFinder list={list} visitor={{ next: "/tournaments" }} />
    </div>
  );
}

/**
 * An event's page: the live one for members, the server's read-only one
 * for visitors (and while sign-in is still loading).
 */
export function TournamentForEveryone({
  page,
  news,
  fallbackHostId,
}: {
  page: PublicHostedPage;
  news: PublicTeamPost[];
  fallbackHostId?: string;
}) {
  const { user } = useAuth();
  if (user) return <TournamentPage tournamentId={page.tournament.id} fallbackHostId={fallbackHostId} />;
  return <VisitorTournament page={page} news={news} />;
}

function VisitorTournament({ page, news }: { page: PublicHostedPage; news: PublicTeamPost[] }) {
  const router = useRouter();
  const path = usePathname();
  const params = useSearchParams();
  const next = `${path}${params.size ? `?${params.toString()}` : ""}`;
  // Another division's games come from the server: ?division= rereads the page.
  const select = useCallback(
    (divisionId: string) => {
      const q = new URLSearchParams(params);
      q.set("division", divisionId);
      router.replace(`${path}?${q.toString()}`, { scroll: false });
    },
    [params, path, router],
  );
  const s = usePublicTournamentState(page, news, next, select);
  const live = page.tournament.status === "live";
  useEffect(() => {
    if (!live) return;
    const timer = setInterval(() => router.refresh(), liveRefreshMs);
    return () => clearInterval(timer);
  }, [live, router]);
  return <TournamentView s={s} />;
}

/** The page's state as useTournament keeps it, from the public answer: read-only, nobody's teams. */
function usePublicTournamentState(page: PublicHostedPage, news: PublicTeamPost[], next: string, select: (id: string) => void): TournamentState {
  return useMemo(() => {
    const p = page.tournament;
    const t: Doc<TournamentDoc> = {
      ...p,
      bidFee: p.bidFee ? { ...p.bidFee, instructions: "" } : null,
      teamFee: p.teamFee ? { ...p.teamFee, instructions: "" } : null,
      format: null,
    };
    const divisions: Array<Doc<DivisionDoc>> = page.divisions.map((d) => ({
      ...d,
      captains: {},
      teams: d.teams.map((x) => ({ ...x, captainId: null, playerIds: [], playerNames: {} })),
    }));
    const entries: Array<Doc<EntryDoc>> = page.entries.map((e) => ({ ...e, captainIds: [] }));
    const division = divisions.find((d) => d.id === page.divisionId) ?? null;
    const games: EngineGame[] = page.games.map((g) => engineGame(g.id, g));
    const liveById = new Map(page.games.map((g) => [g.id, g.live as unknown]));
    // Read-only: the server's running scores while they're fresh.
    const liveOf = (g: EngineGame) => (g.status === "scheduled" ? serverLive(g, liveById.get(g.id), Date.now()) : null);
    const entryOf = (teamId: string) => entries.find((e) => e.id === teamId) ?? null;
    return {
      id: p.id,
      uid: undefined,
      user: null,
      visitor: true,
      visitorNext: next,
      publicNews: news,
      loaded: true,
      error: null,
      t,
      manager: false,
      host: null,
      divisions,
      division,
      divisionId: page.divisionId,
      selectDivision: (id: string | null) => {
        if (id && id !== page.divisionId) select(id);
      },
      entries,
      entryOf,
      entriesIn: (div: string, status?: EntryDoc["status"]) => entries.filter((e) => e.divisionId === div && (!status || e.status === status)),
      entriesWith: (status: EntryDoc["status"]) => entries.filter((e) => e.status === status),
      myTeams: [],
      myAdminTeams: [],
      myEntries: [],
      myTeamIds: new Set<string>(),
      myDivisionId: null,
      teamsToEnter: [],
      myActiveEntry: null,
      games,
      gamesLoaded: true,
      published: games.length > 0,
      teamName: (teamId: string | null | undefined) => (teamId ? (page.names[teamId] ?? "Team") : "TBD"),
      captainOf: new Set<string>(),
      myUpcoming: [],
      liveOf,
      liveGames: games.filter((g) => liveOf(g) !== null),
      canKeepLive: () => false,
      live: noLiveControls,
    };
  }, [page, news, next, select]);
}
