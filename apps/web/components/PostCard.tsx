"use client";
import { type PublicPost, type WorkoutActivity, workoutActivityLabels } from "@stall10/shared";
import Link from "next/link";
import { type ReactNode, useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { Comments } from "./Comments";
import { Composer } from "./Composer";
import { LocalTime } from "./LocalTime";
import { MemberImage } from "./MemberImage";
import { PostActions } from "./PostActions";

function workoutLine(w: NonNullable<PublicPost["workout"]>): string {
  const parts: string[] = [];
  if (w.activity) parts.push(workoutActivityLabels[w.activity as WorkoutActivity] ?? w.activity);
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

/** The post's kind, as the posts rule names them. */
const kindOf = (p: PublicPost) => (p.repostOf ? "repost" : p.workout ? "workout" : p.event ? "event" : "text");

/** Who wrote [post] and when, linking to their profile and the post. */
function PostHead({
  post,
  standalone,
  note,
  menu,
}: {
  post: PublicPost;
  standalone: boolean;
  note?: string;
  menu?: ReactNode;
}) {
  const author = post.authorName || "A player";
  const time = <LocalTime iso={post.createdAt} style="relative" />;
  const avatar = <Avatar name={author} url={post.authorPhotoUrl} />;
  const profile = post.authorId ? `/players/${encodeURIComponent(post.authorId)}` : null;
  return (
    <header className="post-head">
      {profile ? (
        <Link href={profile} className="post-avatar" tabIndex={-1} aria-hidden="true">
          {avatar}
        </Link>
      ) : (
        avatar
      )}
      <span className="post-who">
        <span className="post-name">
          {profile ? (
            <Link href={profile} className="post-author">
              <b>{author}</b>
            </Link>
          ) : (
            <b className="post-author">{author}</b>
          )}
          {note && <span className="post-reposted">{note}</span>}
        </span>
        {standalone ? (
          <span className="post-time">{time}</span>
        ) : (
          <Link className="post-time" href={`/posts/${encodeURIComponent(post.id)}`}>
            {time}
          </Link>
        )}
      </span>
      {menu}
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

/** Edit and delete, for the post's author. */
function OwnerMenu({ onEdit, onDelete }: { onEdit: () => void; onDelete: () => void }) {
  return (
    <details className="post-menu">
      <summary aria-label="Post options">⋯</summary>
      <div className="menu-list">
        <button
          type="button"
          onClick={(e) => {
            (e.currentTarget.closest("details") as HTMLDetailsElement).open = false;
            onEdit();
          }}
        >
          Edit
        </button>
        <button type="button" className="danger" onClick={onDelete}>
          Delete
        </button>
      </div>
    </details>
  );
}

/**
 * A player's post. A repost shows the reposter's note over the original
 * as it is now, as the app does. `standalone` (the post's own page) drops
 * the link to itself and opens its comments. Its author edits or deletes
 * it in place; members like, repost and comment (PostActions, Comments).
 */
export function PostCard({ post: initial, standalone = false }: { post: PublicPost; standalone?: boolean }) {
  const { user } = useAuth();
  const [post, setPost] = useState(initial);
  const [editing, setEditing] = useState(false);
  const [deleted, setDeleted] = useState(false);
  const [showComments, setShowComments] = useState(standalone);
  const [error, setError] = useState<string | null>(null);
  // A live page passes the post again when it changes (an edit elsewhere,
  // new counts); keep what's being edited here.
  useEffect(() => {
    if (!editing) setPost(initial);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only a new post from the page.
  }, [initial]);

  if (deleted) return null;
  const mine = !!user && user.uid === post.authorId;
  const target = post.repostOf ? post.original : post;

  async function remove() {
    if (!user || !confirm(post.repostOf ? "Take back this repost?" : "Delete this post? This can't be undone.")) return;
    setError(null);
    try {
      await callApi(user, `/v1/posts/${encodeURIComponent(post.id)}`, { method: "DELETE" });
      setDeleted(true);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Couldn't delete it. Try again.");
    }
  }

  const menu = mine && !editing ? <OwnerMenu onEdit={() => setEditing(true)} onDelete={() => void remove()} /> : undefined;
  const editor = editing && (
    <Composer
      editing={{ id: post.id, body: post.body ?? "", links: post.links ?? [], images: post.images ?? [], kind: kindOf(post) }}
      autoFocus
      onCancel={() => setEditing(false)}
      onSaved={(r, saved) => {
        // Show the edit at once: its words and links as sent, and the photos kept.
        setPost((p) => ({
          ...p,
          body: saved.body,
          links: saved.links,
          images: r.images.map((i) => ({ ...i, url: p.images?.find((x) => x.path === i.path)?.url ?? "" })),
        }));
        setEditing(false);
      }}
    />
  );
  const footer = (
    <>
      <PostActions post={post} onComment={target ? () => setShowComments((s) => !s) : undefined} />
      {error && <p className="post-error">{error}</p>}
      {showComments && target && (
        <Comments postId={target.id} postAuthorId={target.authorId} autoFocus={!standalone} />
      )}
    </>
  );

  if (!post.repostOf) {
    return (
      <article className="post">
        <PostHead post={post} standalone={standalone} menu={menu} />
        {editor || <PostContent post={post} />}
        {footer}
      </article>
    );
  }
  const original = post.original;
  return (
    <article className="post">
      <PostHead post={post} standalone={standalone} note="reposted" menu={menu} />
      {editor || (post.body && <p className="post-body">{post.body}</p>)}
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
      {footer}
    </article>
  );
}
