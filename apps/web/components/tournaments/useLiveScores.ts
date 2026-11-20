"use client";
// Live running scores on an event's page (HostedTournamentViewModel's live
// scores in the app): what each game's running score is now, who may keep
// it, and setting it. A tap shows at once and is sent in the background,
// absolute scores, each game's latest only, one request at a time, so
// quick taps aren't lost; a failed send goes back to the server's score.
import { type EngineGame, hasTeams, inLiveWindow, isLiveGame, liveScoreOf } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { divisionPath } from "./useTournament";

export interface RunningScore {
  scoreA: number;
  scoreB: number;
}

/** Re-checks what's live (and the live window) this often. */
const tickMs = 60_000;

/** The current time, ticking each minute. */
export function useNow(): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), tickMs);
    return () => clearInterval(t);
  }, []);
  return now;
}

/** The server's running score of [raw] (a game doc's `live`) when the game is live at [now]. */
export function serverLive(g: EngineGame, raw: unknown, now: number): RunningScore | null {
  if (!isLiveGame({ status: g.status, live: raw }, now)) return null;
  const l = liveScoreOf(raw);
  return l ? { scoreA: l.scoreA, scoreB: l.scoreB } : null;
}

/**
 * Whether the viewer may keep [g]'s running score now (canKeepLive): the
 * event is under way, the game has both teams and is still to be scored,
 * the viewer captains either team or manages the event, and it's the
 * game's day. The API checks all of it again.
 */
export function canKeepLiveScore(o: {
  signedIn: boolean;
  status: string | undefined;
  manager: boolean;
  captainOf: Set<string>;
  g: EngineGame;
  now: number;
}): boolean {
  const { g } = o;
  if (!o.signedIn || !o.status || o.status === "draft" || o.status === "finished") return false;
  if (!hasTeams(g) || g.status !== "scheduled") return false;
  if (!o.manager && !o.captainOf.has(g.teamA ?? "") && !o.captainOf.has(g.teamB ?? "")) return false;
  return inLiveWindow(g.startsAt, o.now);
}

/**
 * A member's running scores for the selected division: [liveById] is each
 * game's stored `live` (from the games listener), which takes over again
 * once nothing is on its way.
 */
export function useLiveScores(user: User | null | undefined, tournamentId: string, divisionId: string | null, liveById: Map<string, unknown>) {
  // Running scores tapped that the server may not have yet, by game id.
  const [pending, setPending] = useState<Map<string, RunningScore>>(() => new Map());
  const pendingRef = useRef(pending);
  const unsent = useRef(new Set<string>());
  const sending = useRef(false);
  const [error, setError] = useState<string | null>(null);
  const [stopping, setStopping] = useState(false);

  const put = useCallback((next: Map<string, RunningScore>) => {
    pendingRef.current = next;
    setPending(next);
  }, []);

  // Another division: nothing of the last one's is pending.
  useEffect(() => {
    unsent.current.clear();
    put(new Map());
  }, [divisionId, put]);

  // The server's running scores take over once nothing is on its way.
  useEffect(() => {
    if (!sending.current && pendingRef.current.size > 0) put(new Map());
  }, [liveById, put]);

  const send = useCallback(
    async (div: string) => {
      if (!user || sending.current) return;
      sending.current = true;
      try {
        while (unsent.current.size > 0) {
          const gameId = unsent.current.values().next().value as string;
          unsent.current.delete(gameId);
          const want = pendingRef.current.get(gameId);
          if (!want) continue;
          try {
            await callApi(user, `${divisionPath(tournamentId, div)}/games/${encodeURIComponent(gameId)}/live`, {
              method: "POST",
              body: { scoreA: want.scoreA, scoreB: want.scoreB },
            });
            setError(null);
          } catch (e) {
            // Back to the server's score; a newer tap still goes.
            if (pendingRef.current.get(gameId) === want) {
              const next = new Map(pendingRef.current);
              next.delete(gameId);
              put(next);
            }
            setError(problem(e));
          }
        }
      } finally {
        sending.current = false;
      }
    },
    [user, tournamentId, put],
  );

  /** Sets [gameId]'s running score to [a]–[b] (0–0 starts the game). */
  const setLive = useCallback(
    (gameId: string, a: number, b: number) => {
      if (!divisionId) return;
      const next = new Map(pendingRef.current);
      next.set(gameId, { scoreA: Math.min(Math.max(a, 0), 99), scoreB: Math.min(Math.max(b, 0), 99) });
      put(next);
      unsent.current.add(gameId);
      void send(divisionId);
    },
    [divisionId, put, send],
  );

  /** Takes [gameId]'s running score off; true when it's off. */
  const stopLive = useCallback(
    async (gameId: string): Promise<boolean> => {
      if (!user || !divisionId) return false;
      unsent.current.delete(gameId);
      if (pendingRef.current.has(gameId)) {
        const next = new Map(pendingRef.current);
        next.delete(gameId);
        put(next);
      }
      setStopping(true);
      try {
        await callApi(user, `${divisionPath(tournamentId, divisionId)}/games/${encodeURIComponent(gameId)}/live`, { method: "DELETE" });
        setError(null);
        return true;
      } catch (e) {
        setError(problem(e));
        return false;
      } finally {
        setStopping(false);
      }
    },
    [user, divisionId, tournamentId, put],
  );

  return useMemo(() => ({ pending, error, setError, stopping, setLive, stopLive }), [pending, error, stopping, setLive, stopLive]);
}

/** What the page's state carries for keeping running scores (none for visitors). */
export interface LiveControls {
  error: string | null;
  setError: (e: string | null) => void;
  stopping: boolean;
  setLive: (gameId: string, a: number, b: number) => void;
  stopLive: (gameId: string) => Promise<boolean>;
}

/** A visitor's: nothing to keep. */
export const noLiveControls: LiveControls = {
  error: null,
  setError: () => {},
  stopping: false,
  setLive: () => {},
  stopLive: async () => false,
};
