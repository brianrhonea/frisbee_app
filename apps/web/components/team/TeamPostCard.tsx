"use client";
import { type PublicTeamPost, teamPostCommentLabel } from "@stall10/shared";
import { type ReactNode, useState } from "react";
import { LocalTime } from "../LocalTime";
import { MemberImage } from "../MemberImage";
import { LinkedText } from "../LinkedText";

/** A team post as the browser reads it: the public shape, plus the member-only flag. */
export type TeamPostView = PublicTeamPost & {
  public?: boolean;
  images?: Array<{ path: string; name?: string; url?: string }>;
  location?: string;
  /** Kept by the follows functions (F24); missing reads as 0. Members only. */
  commentCount?: number;
};

const isWebLink = (url: string) => /^https?:\/\//i.test(url);

/**
 * A team's post or announcement (TeamPost in the app). A [pinned] post
 * says so on top (redesign F24); with [comments] (members) it ends with
 * its comment count, which opens the thread [comments] renders.
 */
export function TeamPostCard({
  post,
  teamName,
  showAudience,
  actions,
  pinned = false,
  comments,
}: {
  post: TeamPostView;
  teamName: string;
  showAudience?: boolean;
  /** Edit, delete and pin, for the team's admins. */
  actions?: ReactNode;
  pinned?: boolean;
  comments?: () => ReactNode;
}) {
  const images = post.images ?? [];
  const links = (post.links ?? []).filter(isWebLink);
  const [open, setOpen] = useState(false);
  return (
    <article className={`post${pinned ? " post-pinned" : ""}`}>
      {pinned && (
        <p className="post-pinned-label">
          <span aria-hidden="true">📌</span> Pinned
        </p>
      )}
      <header className="post-head">
        <div className="team-post-who">
          <b>{post.title || teamName}</b>
          <span className="post-time">
            {post.authorName ? `${post.authorName} · ` : ""}
            <LocalTime iso={post.createdAt} style="relative" />
          </span>
        </div>
        {showAudience && post.public !== true && <span className="post-tag">Members only</span>}
        {actions}
      </header>
      {post.location && <p className="muted small post-place" style={{ margin: "4px 0 0" }}>{post.location}</p>}
      {post.body && <p className="post-body"><LinkedText text={post.body} /></p>}
      {images.length > 0 && (
        <div className={`post-images n${Math.min(images.length, 4)}`}>
          {images.slice(0, 4).map((img) => (
            <MemberImage key={img.path} path={img.path} url={img.url ?? ""} alt={img.name ?? ""} />
          ))}
        </div>
      )}
      {links.length > 0 && (
        <ul className="post-links">
          {links.map((l) => (
            <li key={l}>
              <a href={l} target="_blank" rel="noopener nofollow ugc">
                {l.replace(/^https?:\/\//i, "")}
              </a>
            </li>
          ))}
        </ul>
      )}
      {comments && (
        <div className="post-actions team-post-actions">
          <button type="button" className="text-btn" aria-expanded={open} onClick={() => setOpen((o) => !o)}>
            {teamPostCommentLabel(post.commentCount)}
          </button>
        </div>
      )}
      {comments && open && comments()}
    </article>
  );
}
