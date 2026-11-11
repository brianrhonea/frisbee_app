import type { PublicPost } from "@stall10/shared";
import Link from "next/link";
import { Avatar } from "./Avatar";
import { LocalTime } from "./LocalTime";
import { MemberImage } from "./MemberImage";

function workoutLine(w: NonNullable<PublicPost["workout"]>): string {
  const parts: string[] = [];
  if (w.activity) parts.push(w.activity);
  const mins = w.durationMinutes ?? (w.durationSeconds ? Math.round(w.durationSeconds / 60) : undefined);
  if (mins) parts.push(`${mins} min`);
  if (w.distanceKm) parts.push(`${w.distanceKm} km`);
  if (w.effort) parts.push(`effort ${w.effort}/10`);
  return parts.join(" · ");
}

/** Shown text for a link: its host and path, without the scheme. */
function linkLabel(url: string): string {
  try {
    const u = new URL(url);
    return (u.host + u.pathname).replace(/\/$/, "");
  } catch {
    return url;
  }
}

/** Only web links become anchors (never javascript: or other schemes). */
const isWebLink = (url: string) => /^https?:\/\//i.test(url);

/**
 * A player's post. `standalone` drops the link to itself; `member` is a
 * signed-in view (photos through Storage, no sign-up prompt).
 */
export function PostCard({ post, standalone = false, member = false }: { post: PublicPost; standalone?: boolean; member?: boolean }) {
  const author = post.authorName || "A player";
  const links = (post.links ?? []).filter(isWebLink);
  const who = (
    <>
      <Avatar name={author} url={post.authorPhotoUrl} />
      <b>{author}</b>
    </>
  );
  return (
    <article className="post">
      {post.repostOf && (
        <p className="post-repost">
          Reposted from{" "}
          <Link href={`/players/${encodeURIComponent(post.repostOf.authorId)}`}>
            {post.repostOf.authorName || "a player"}
          </Link>
        </p>
      )}
      <header className="post-head">
        {post.authorId ? (
          <Link href={`/players/${encodeURIComponent(post.authorId)}`} className="post-author">
            {who}
          </Link>
        ) : (
          <span className="post-author">{who}</span>
        )}
        {standalone ? (
          <span className="post-time">
            <LocalTime iso={post.createdAt} style="relative" />
          </span>
        ) : (
          <Link className="post-time" href={`/posts/${encodeURIComponent(post.id)}`}>
            <LocalTime iso={post.createdAt} style="relative" />
          </Link>
        )}
      </header>
      {post.tournamentName && <p className="post-tag">{post.tournamentName}</p>}
      {post.body && <p className="post-body">{post.body}</p>}
      {post.workout && (
        <div className="post-box">
          <b>Workout</b> {workoutLine(post.workout)}
          {post.workout.exercises?.length ? (
            <ul>
              {post.workout.exercises.map((x, i) => (
                <li key={i}>
                  {x.name}
                  {x.sets ? ` · ${x.sets}×${x.reps ?? ""}` : ""}
                  {x.weight ? ` · ${x.weight}` : ""}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      )}
      {post.event && (
        <div className="post-box">
          <b>{post.event.title || "Event"}</b>
          <div className="muted">
            <LocalTime iso={post.event.startsAt} style="dateTime" />
            {post.event.location ? ` · ${post.event.location}` : ""}
          </div>
          {post.event.teamId && post.event.teamName && (
            <Link href={`/teams/${encodeURIComponent(post.event.teamId)}`}>{post.event.teamName}</Link>
          )}
        </div>
      )}
      {post.images?.length ? (
        <div className={`post-images n${Math.min(post.images.length, 4)}`}>
          {post.images.slice(0, 4).map((img) => (
            <a key={img.path} href={img.url} target="_blank" rel="noopener">
              <MemberImage path={img.path} url={img.url} alt={img.name ?? ""} signedIn={member} />
            </a>
          ))}
        </div>
      ) : null}
      {links.length ? (
        <ul className="post-links">
          {links.map((l) => (
            <li key={l}>
              <a href={l} target="_blank" rel="noopener nofollow ugc">
                {linkLabel(l)}
              </a>
            </li>
          ))}
        </ul>
      ) : null}
      <footer className="post-counts">
        <span>
          {post.likeCount} {post.likeCount === 1 ? "like" : "likes"}
        </span>
        <span>
          {post.repostCount} {post.repostCount === 1 ? "repost" : "reposts"}
        </span>
        {post.commentCount ? (
          <span>
            {post.commentCount} {post.commentCount === 1 ? "comment" : "comments"}
          </span>
        ) : null}
        {member ? (
          <a className="post-join" href={`stall10://open/p/${encodeURIComponent(post.id)}`}>
            Like and reply in the app
          </a>
        ) : (
          <Link className="post-join" href="/sign-up">
            Sign up to like and reply
          </Link>
        )}
      </footer>
    </article>
  );
}
