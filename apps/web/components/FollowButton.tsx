"use client";
import { type FollowResult, type FollowType, followKey } from "@stall10/shared";
import Link from "next/link";
import { useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "./AuthProvider";

/**
 * Follow a player, team or tournament. Live: shows Following (hover to
 * unfollow) with a bell for post notifications, or Requested for a private
 * profile until its owner accepts. Visitors get a sign-up link; on your
 * own profile it's Edit profile.
 */
export function FollowButton({
  type = "user",
  targetId,
  groupId,
  isPrivate = false,
  signUpNext,
}: {
  type?: FollowType;
  targetId: string;
  /** A tournament's host. */
  groupId?: string;
  /** A private player profile: following asks first. */
  isPrivate?: boolean;
  /** Where sign-up returns visitors to. */
  signUpNext?: string;
}) {
  const { user } = useAuth();
  const key = followKey(type, groupId ? `${groupId}_${targetId}` : targetId);
  const follow = useLiveDoc<{ notify?: boolean }>(user ? `users/${user.uid}/follows/${key}` : null);
  const request = useLiveDoc(user && type === "user" && isPrivate ? `profiles/${targetId}/followRequests/${user.uid}` : null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (user === undefined) return null;
  if (!user) {
    return (
      <Link
        className="btn btn-primary btn-small"
        href={`/sign-up${signUpNext ? `?next=${encodeURIComponent(signUpNext)}` : ""}`}
      >
        Sign up to follow
      </Link>
    );
  }
  if (type === "user" && targetId === user.uid) {
    return (
      <Link className="btn btn-small" href="/settings/profile">
        Edit profile
      </Link>
    );
  }
  const me = user;
  const loading = follow.data === undefined || (isPrivate && type === "user" && request.data === undefined);

  async function run(fn: () => Promise<unknown>) {
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Something went wrong. Try again.");
    } finally {
      setBusy(false);
    }
  }

  let button;
  if (follow.data) {
    const notify = follow.data.notify === true;
    button = (
      <>
        <button
          type="button"
          className="btn btn-small follow-on"
          disabled={busy}
          onClick={() => void run(() => callApi(me, `/v1/follows/${encodeURIComponent(key)}`, { method: "DELETE" }))}
        >
          <span className="when-idle">Following</span>
          <span className="when-hover">Unfollow</span>
        </button>
        <button
          type="button"
          className={`icon-btn bell${notify ? " on" : ""}`}
          aria-pressed={notify}
          title={notify ? "Notifying you of new posts" : "Get notified of new posts"}
          disabled={busy}
          onClick={() =>
            void run(() =>
              callApi(me, `/v1/follows/${encodeURIComponent(key)}`, { method: "PATCH", body: { notify: !notify } }),
            )
          }
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill={notify ? "currentColor" : "none"} stroke="currentColor" strokeWidth="1.9" aria-hidden="true">
            <path d="M6 16V11a6 6 0 1 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0" />
          </svg>
          <span className="sr-only">Post notifications</span>
        </button>
      </>
    );
  } else if (request.data) {
    button = (
      <button
        type="button"
        className="btn btn-small"
        title="Take back your request"
        disabled={busy}
        onClick={() =>
          void run(() => callApi(me, `/v1/follows/requests/${encodeURIComponent(targetId)}`, { method: "DELETE" }))
        }
      >
        Requested
      </button>
    );
  } else {
    button = (
      <button
        type="button"
        className="btn btn-primary btn-small"
        disabled={busy || loading}
        onClick={() =>
          void run(() =>
            callApi<FollowResult>(me, "/v1/follows", {
              method: "PUT",
              body: { type, targetId, ...(groupId && { groupId }) },
            }),
          )
        }
      >
        {isPrivate && type === "user" ? "Ask to follow" : "Follow"}
      </button>
    );
  }
  return (
    <span className="follow">
      {button}
      {error && <span className="post-error">{error}</span>}
    </span>
  );
}
