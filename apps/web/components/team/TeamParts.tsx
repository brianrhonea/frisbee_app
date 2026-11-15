"use client";
import { type PlayDoc, playCategoryLabels } from "@stall10/shared";
import Link from "next/link";
import { useLiveQuery } from "@/lib/live";
import { LiveList } from "../StatusViews";
import { useTeamHub } from "./TeamContext";
import { MembersOnlySection } from "./TeamNav";
import { PlayField } from "./playbook/PlayField";
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
          <HostedTournamentsSection teamId={teamId} kind={kind} manager={viewer.can("manageEvents")} member />
          <GroupTournamentsList />
        </>
      )}
    </div>
  );
}

function Playbook({ teamId, editor }: { teamId: string; editor: boolean }) {
  const plays = useLiveQuery<PlayDoc>(`teams/${teamId}/plays`, [], "plays");
  const base = `/teams/${encodeURIComponent(teamId)}/plays`;
  return (
    <>
      {editor && (
        <div className="home-actions">
          <Link href={`${base}/new`} className="btn btn-primary btn-small">
            New play
          </Link>
        </div>
      )}
      <LiveList live={plays} empty={editor ? "No plays yet. Draw your first one." : "No plays yet."}>
        {(rows) => (
          <div className="play-grid">
            {rows
              .slice()
              .sort((a, b) => (a.category ?? "").localeCompare(b.category ?? "") || (a.name ?? "").localeCompare(b.name ?? ""))
              .map((p) => (
                <Link key={p.id} href={`${base}/${encodeURIComponent(p.id)}`} className="card play-card">
                  <PlayField elements={p.elements ?? []} arrows={p.arrows ?? []} label={`${p.name ?? "Play"} diagram`} />
                  <h3>{p.name || "Play"}</h3>
                  <p className="muted small">
                    {playCategoryLabels[p.category ?? "offense"] ?? "Play"}
                    {p.steps?.length ? ` · ${p.steps.length + 1} steps` : ""}
                  </p>
                  {p.notes && <p className="small play-notes">{p.notes}</p>}
                </Link>
              ))}
          </div>
        )}
      </LiveList>
    </>
  );
}
