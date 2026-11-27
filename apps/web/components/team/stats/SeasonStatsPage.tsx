"use client";
import { statSheetOfGames } from "@stall10/shared";
import Link from "next/link";
import type { ReactNode } from "react";
import { useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { nameMap, statsUrl, useStatsGames, useStatsPlayers } from "./data";
import { StatSheetTable } from "./StatSheetTable";
import "./stats.css";
import { ErrorNote } from "@/components/StatusViews";

/** Back to the Stats tab. */
export function BackToStats({ teamId, label = "Stats" }: { teamId: string; label?: string }) {
  return (
    <Link href={`/teams/${encodeURIComponent(teamId)}/stats`} className="text-btn">
      ← {label}
    </Link>
  );
}

/** Members of a team only: communities keep no stats. */
export function StatsGate({ children }: { children: ReactNode }) {
  const { kind, viewer } = useTeamHub();
  if (kind !== "team") return <p className="empty">Communities don&apos;t keep stats.</p>;
  if (viewer.state === "loading") return <p className="muted" aria-busy="true">Loading…</p>;
  if (viewer.state !== "member") return <MembersOnlySection what="stats" />;
  return <>{children}</>;
}

/** Every player's stats over every game (SeasonStatsScreen). */
export function SeasonStatsPage() {
  return (
    <StatsGate>
      <Season />
    </StatsGate>
  );
}

function Season() {
  const { teamId } = useTeamHub();
  const games = useStatsGames(teamId);
  const players = useStatsPlayers(teamId);
  return (
    <div className="stack">
      <BackToStats teamId={teamId} />
      <h2 className="card-title">Season stats</h2>
      {games.error ? (
        <ErrorNote>{games.error}</ErrorNote>
      ) : !games.data ? (
        <p className="muted" aria-busy="true">Loading…</p>
      ) : (
        <StatSheetTable sheet={statSheetOfGames(games.data)} nameOf={nameMap(players.data)} />
      )}
      <Link href={statsUrl(teamId, "/players")} className="text-btn">
        Roster players
      </Link>
    </div>
  );
}
