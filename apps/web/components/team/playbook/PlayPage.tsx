"use client";
import { type PlayDoc, playCategoryLabels } from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { useLiveDoc } from "@/lib/live";
import { useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import { PlayEditor, PlayViewer } from "./PlayEditor";

/**
 * One play (/teams/:id/plays/:playId, or "new"): admins who manage the
 * team draw and edit it; other members watch it play.
 */
export function PlayPage({ playId }: { playId: string }) {
  const { teamId, kind, viewer } = useTeamHub();
  const isNew = playId === "new";
  const member = viewer.state === "member";
  const play = useLiveDoc<PlayDoc>(member && !isNew ? `teams/${teamId}/plays/${playId}` : null);
  const editor = member && viewer.can("manageTeam");
  const router = useRouter();
  // A saved whiteboard opens on the whiteboard, not in the play editor.
  const whiteboard = play.data?.kind === "whiteboard";
  useEffect(() => {
    if (whiteboard) router.replace(`/teams/${encodeURIComponent(teamId)}/whiteboards/${encodeURIComponent(playId)}`);
  }, [whiteboard, router, teamId, playId]);
  const back = (
    <Link href={`/teams/${encodeURIComponent(teamId)}/playbook`} className="text-btn">
      ← Playbook
    </Link>
  );

  if (kind !== "team") return <p className="empty">Communities don&apos;t have a playbook.</p>;
  if (!member) return <MembersOnlySection what="playbook" />;
  if (isNew) {
    if (!editor) return <p className="empty">Only the team&apos;s admins can add plays. {back}</p>;
    return (
      <div className="stack">
        {back}
        <PlayEditor teamId={teamId} id={null} />
      </div>
    );
  }
  if (play.error) return <p className="form-error">{play.error}</p>;
  if (play.data === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
  if (play.data === null) return <p className="empty">That play was deleted. {back}</p>;
  if (whiteboard) return <p className="muted" aria-busy="true">Opening the whiteboard…</p>;
  return (
    <div className="stack">
      {back}
      {editor ? (
        // Keyed by id: later snapshots (our own saves) don't reset the drawing.
        <PlayEditor key={play.data.id} teamId={teamId} id={play.data.id} initial={play.data} />
      ) : (
        <>
          <h2 className="card-title">
            {play.data.name || "Play"} <span className="muted small">{playCategoryLabels[play.data.category ?? "offense"] ?? ""}</span>
          </h2>
          <PlayViewer play={play.data} />
        </>
      )}
    </div>
  );
}
