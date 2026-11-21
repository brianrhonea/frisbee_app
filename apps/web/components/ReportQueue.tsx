"use client";
import { type ReportInfo, type ReportTarget, reportReasonLabels } from "@stall10/shared";
import Link from "next/link";
import type { ReactNode } from "react";
import { LocalTime } from "./LocalTime";

/** Where the reported thing is, for a reviewer to look at it in place. */
export function reportedLink(t: ReportTarget): string | null {
  const e = encodeURIComponent;
  switch (t.kind) {
    case "post":
    case "comment":
      return `/posts/${e(t.postId)}`;
    case "teamPost":
    case "teamPostComment":
      return `/teams/${e(t.teamId)}`;
    case "teamMessage":
      return `/teams/${e(t.teamId)}/chat?room=${e(t.roomId)}`;
    case "user":
      return `/players/${e(t.uid)}`;
    case "directMessage":
      return null;
  }
}

const kindLabel: Record<ReportTarget["kind"], string> = {
  post: "Post",
  comment: "Comment",
  teamPost: "Team post",
  teamPostComment: "Comment on a team post",
  teamMessage: "Team chat message",
  directMessage: "Direct message",
  user: "Profile",
};

/**
 * One report in a review queue (the team's Reports, or staff's): what it
 * is, why, who wrote it, the snapshot taken when it was reported, and
 * [actions].
 */
export function ReportCard({ report: r, actions }: { report: ReportInfo; actions: ReactNode }) {
  const link = reportedLink(r.target);
  return (
    <li className="report-card">
      <p className="report-head">
        <b>{kindLabel[r.target.kind]}</b> by <Link href={`/players/${encodeURIComponent(r.authorId)}`}>{r.authorName || "a player"}</Link>
        {r.teamName && <> in {r.teamName}</>}
        {r.authorSuspended && <span className="post-tag">Suspended</span>}
        <span className="muted small">
          {" "}
          · <LocalTime iso={r.createdAt ?? undefined} style="relative" />
        </span>
      </p>
      <p className="report-reason-line">
        {reportReasonLabels[r.reason]}
        {r.reporterName && <span className="muted small"> · reported by {r.reporterName}</span>}
      </p>
      {r.details && <p className="report-details">“{r.details}”</p>}
      {(r.snapshot.text || r.snapshot.images.length > 0) && (
        <blockquote className="report-snapshot">
          {r.snapshot.text && <p>{r.snapshot.text}</p>}
          {r.snapshot.images.map((u) => (
            // eslint-disable-next-line @next/next/no-img-element -- evidence, shown as it was stored.
            <img key={u} src={u} alt="" loading="lazy" />
          ))}
        </blockquote>
      )}
      {r.note && <p className="muted small">Note: {r.note}</p>}
      <div className="form-actions">
        {link && (
          <Link className="btn btn-small" href={link}>
            Open
          </Link>
        )}
        {actions}
      </div>
    </li>
  );
}
