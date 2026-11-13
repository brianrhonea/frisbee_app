import type { PublicPost } from "@stall10/shared";
import Link from "next/link";
import { Avatar } from "./Avatar";
import { LocalTime } from "./LocalTime";
import { MemberImage } from "./MemberImage";
import { PostActions } from "./PostActions";

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

/** Who wrote [post] and when, linking to their profile and the post. */
function PostHead({ post, standalone, note }: { post: PublicPost; standalone: boolean; note?: string }) {
  const author = post.authorName || "A player";
  const who = (
    <>
      <Avatar name={author} url={post.authorPhotoUrl} />
      <b>{author}</b>
    </>
  );
  const time = <LocalTime iso={post.createdAt} style="relative" />;
  return (
    <header className="post-head">
      {post.authorId ? (
        <Link href={`/players/${encodeURIComponent(post.authorId)}`} className="post-author">
          {who}
        </Link>
      ) : (
        <span className="post-author">{who}</span>
      )}
      {note && <span className="post-reposted">{note}</span>}
      {standalone ? (
        <span className="post-time">{time}</span>
      ) : (
        <Link className="post-time" href={`/posts/${encodeURIComponent(post.id)}`}>
          {time}
        </Link>
      )}
    </header>
  );
}

/** A post's own content: text, workout, event, photos and links. */
function PostContent({ post }: { post: PublicPost }) {
  const links = (post.links ?? []).filter(isWebLink);
  return (
    <>
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
              <MemberImage path={img.path} url={img.url} alt={img.name ?? ""} />
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
    </>
  );
}

/**
 * A player's post. A repost shows the reposter's note over the original
 * as it is now, as the app does. `standalone` drops the link to itself.
 * Likes and reposts (PostActions) follow whoever is signed in.
 */
export function PostCard({ post, standalone = false }: { post: PublicPost; standalone?: boolean }) {
  if (!post.repostOf) {
    return (
      <article className="post">
        <PostHead post={post} standalone={standalone} />
        <PostContent post={post} />
        <PostActions post={post} />
      </article>
    );
  }
  const original = post.original;
  return (
    <article className="post">
      <PostHead post={post} standalone={standalone} note="reposted" />
      {post.body && <p className="post-body">{post.body}</p>}
      {original ? (
        <div className="post-original">
          <PostHead post={original} standalone={false} />
          <PostContent post={original} />
        </div>
      ) : (
        <p className="post-original post-missing">
          {post.repostOf.authorName ? `${post.repostOf.authorName}'s post` : "This post"} was deleted.
        </p>
      )}
      <PostActions post={post} />
    </article>
  );
}
