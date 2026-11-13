import type { PublicTeamPost } from "@stall10/shared";
import { LocalTime } from "../LocalTime";
import { MemberImage } from "../MemberImage";

/** A team post as the browser reads it: the public shape, plus the member-only flag. */
export type TeamPostView = PublicTeamPost & { public?: boolean; images?: Array<{ path: string; name?: string; url?: string }> };

const isWebLink = (url: string) => /^https?:\/\//i.test(url);

/** A team's post or announcement (TeamPost in the app). */
export function TeamPostCard({ post, teamName, showAudience }: { post: TeamPostView; teamName: string; showAudience?: boolean }) {
  const images = post.images ?? [];
  const links = (post.links ?? []).filter(isWebLink);
  return (
    <article className="post">
      <header className="post-head">
        <div className="team-post-who">
          <b>{post.title || teamName}</b>
          <span className="post-time">
            {post.authorName ? `${post.authorName} · ` : ""}
            <LocalTime iso={post.createdAt} style="relative" />
          </span>
        </div>
        {showAudience && post.public !== true && <span className="post-tag">Members only</span>}
      </header>
      {post.location && <p className="muted small" style={{ margin: "4px 0 0" }}>{post.location}</p>}
      {post.body && <p className="post-body">{post.body}</p>}
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
    </article>
  );
}
