"use client";
import { GameTracker, SaveQueue, type StatsGame, type StatsTournament, statsGameBody, statsTournamentBody } from "@stall10/shared";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../../AuthProvider";
import { useTeamHub } from "../TeamContext";
import { apiUrl, statsAccess, useStatsGames, useStatsPlayers, useStatsTournaments } from "./data";

const newId = () =>
  typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now().toString(36)}${Math.random().toString(36).slice(2)}`;

/**
 * One game being tracked (GameTrackerViewModel). The game comes from the
 * listener once; after that this page's copy is the truth, as in the app,
 * so its own saves coming back never undo newer taps. Saves go through one
 * queue for the game and its tournament: milestones at once, plays after
 * 3 s, never more than one request a second, retried with backoff.
 */
export function useGameTracker(gameId: string) {
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const access = statsAccess(viewer);
  const games = useStatsGames(teamId);
  const tournaments = useStatsTournaments(teamId);
  const players = useStatsPlayers(teamId);
  const [, setVersion] = useState(0);
  const [saveError, setSaveError] = useState<string | null>(null);
  const tracker = useRef<GameTracker | null>(null);
  const dirty = useRef<{ game: StatsGame | null; tournament: StatsTournament | null }>({ game: null, tournament: null });
  const userRef = useRef(user);
  userRef.current = user;

  const queue = useMemo(
    () =>
      new SaveQueue<number>(
        async () => {
          const u = userRef.current;
          if (!u) throw new Error("Signed out");
          const d = dirty.current;
          // One request per send, so both documents share the one-a-second cap.
          if (d.game) {
            const g = d.game;
            d.game = null;
            try {
              await callApi(u, apiUrl(teamId, `/stats-games/${encodeURIComponent(g.id)}`), { method: "PUT", body: statsGameBody(g) });
            } catch (e) {
              d.game ??= g;
              throw e;
            }
          } else if (d.tournament) {
            const t = d.tournament;
            d.tournament = null;
            try {
              await callApi(u, apiUrl(teamId, `/stats-tournaments/${encodeURIComponent(t.id)}`), { method: "PUT", body: statsTournamentBody(t) });
            } catch (e) {
              d.tournament ??= t;
              throw e;
            }
          }
          if (d.game || d.tournament) queue.schedule(Date.now(), true);
        },
        (error) =>
          setSaveError(
            error === null
              ? null
              : error instanceof ApiError && error.status === 404
                ? "This game was deleted, so changes can't be saved."
                : "Couldn't save the last change. It's kept on this page and will retry.",
          ),
      ),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- one queue per page.
    [teamId, gameId],
  );

  const found = games.data?.find((g) => g.id === gameId);
  if (!tracker.current && found) {
    tracker.current = new GameTracker(
      found,
      { canEdit: access.keepStats, players: players.data ?? [], tournaments: tournaments.data ?? [], otherGames: [] },
      {
        saveGame: (g, milestone) => {
          dirty.current.game = g;
          queue.schedule(Date.now(), milestone);
        },
        saveTournament: (t) => {
          dirty.current.tournament = t;
          queue.schedule(Date.now(), true);
        },
        newId,
      },
    );
  }
  tracker.current?.setContext({
    canEdit: access.keepStats,
    players: players.data ?? [],
    tournaments: tournaments.data ?? [],
    otherGames: (games.data ?? []).filter((g) => g.id !== gameId),
  });

  // The app flushes when the screen closes; so does this, and when the tab is hidden.
  useEffect(() => {
    const hide = () => document.visibilityState === "hidden" && queue.flush();
    const warn = (e: BeforeUnloadEvent) => {
      if (queue.dirty) {
        queue.flush();
        e.preventDefault();
      }
    };
    document.addEventListener("visibilitychange", hide);
    window.addEventListener("beforeunload", warn);
    return () => {
      document.removeEventListener("visibilitychange", hide);
      window.removeEventListener("beforeunload", warn);
      queue.flush();
    };
  }, [queue]);

  /** Runs a tracker change and redraws. */
  const act = useCallback((fn: (t: GameTracker) => void) => {
    const t = tracker.current;
    if (!t) return;
    fn(t);
    setVersion((v) => v + 1);
  }, []);

  const loaded = games.data !== undefined && tournaments.data !== undefined;
  return {
    tracker: tracker.current,
    act,
    loaded,
    error: games.error ?? tournaments.error ?? players.error,
    saveError,
    canDelete: access.canDelete,
  };
}
