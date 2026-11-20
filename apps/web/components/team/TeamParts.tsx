"use client";
import { useAuth } from "../AuthProvider";
import { TournamentDayCard } from "../tournaments/TournamentDayCard";
import { useTournamentDays } from "../tournaments/useTournamentDays";
import { useTeamHub } from "./TeamContext";
import { MembersOnlySection } from "./TeamNav";
import { Playbook } from "./playbook/Playbook";
import { HostedTournamentsSection } from "../tournaments/TournamentLists";
import { GroupTournamentsList } from "./group_tournaments/GroupTournamentsList";
import { StatsHome } from "./stats/StatsHome";
import { TeamVideos } from "./videos/TeamVideos";

/** The hub's members-only sections with a page each (/teams/:id/playbook …). */
export type TeamPartName = "playbook" | "videos" | "stats" | "tournaments";

/**
 * One of the hub's members-only sections (spec §4): a team's playbook,
 * videos and stats, and any kind's tournaments. Each has its own route so
 * its detail pages highlight its tab; the old /more?tab= links redirect here.
 */
export function TeamPart({ part }: { part: TeamPartName }) {
  const { teamId, kind, viewer } = useTeamHub();
  if (viewer.state !== "member") return <MembersOnlySection what={part} />;
  return (
    <div className="stack">
      {part === "playbook" && <Playbook teamId={teamId} editor={viewer.can("manageTeam")} />}
      {part === "videos" && <TeamVideos />}
      {part === "stats" && <StatsHome />}
      {part === "tournaments" && (
        <>
          {kind === "team" && <TeamTournamentDay teamId={teamId} />}
          <HostedTournamentsSection teamId={teamId} kind={kind} manager={viewer.can("manageEvents")} member />
          <GroupTournamentsList />
        </>
      )}
    </div>
  );
}

/** A member's team on a tournament day: its card above the tournaments, as on the feed. */
function TeamTournamentDay({ teamId }: { teamId: string }) {
  const { user } = useAuth();
  const day = useTournamentDays(user?.uid, teamId)[0];
  return day ? <TournamentDayCard day={day} showTeam={false} /> : null;
}
