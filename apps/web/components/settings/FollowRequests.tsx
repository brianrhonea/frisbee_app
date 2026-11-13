"use client";
import { orderBy } from "firebase/firestore";
import Link from "next/link";
import { useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useLiveQuery } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { LocalTime } from "../LocalTime";
import { useMyProfile } from "./useMyProfile";

interface Request {
  name?: string;
  username?: string | null;
  photoUrl?: string | null;
  createdAt?: string;
}

/** People asking to follow the member's private profile, oldest first. */
export function FollowRequests() {
  const { user } = useAuth();
  const { profile } = useMyProfile();
  const { data, error } = useLiveQuery<Request>(
    user ? `profiles/${user.uid}/followRequests` : null,
    [orderBy("createdAt", "asc")],
    "requests",
  );
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  if (!user) return null;
  const me = user;

  async function answer(uid: string, accept: boolean) {
    setBusy(uid);
    setProblem(null);
    try {
      await callApi(me, `/v1/me/follow-requests/${encodeURIComponent(uid)}${accept ? "/accept" : ""}`, {
        method: accept ? "POST" : "DELETE",
      });
    } catch (e) {
      setProblem(e instanceof ApiError ? e.message : "Something went wrong. Try again.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="card">
      <h2 className="card-title">Follow requests</h2>
      {profile && !profile.private && (
        <p className="muted small">
          Your profile is public, so anyone can follow you. <Link href="/settings/privacy">Make it private</Link> to approve
          followers first.
        </p>
      )}
      {error && <p className="form-error">{error}</p>}
      {problem && <p className="form-error">{problem}</p>}
      {data && data.length === 0 && <p className="empty">No requests right now.</p>}
      <ul className="people-list">
        {(data ?? []).map((r) => (
          <li key={r.id}>
            <Link href={`/players/${encodeURIComponent(r.id)}`} className="row-link">
              <Avatar name={r.name || "?"} url={r.photoUrl ?? undefined} size={38} />
              <span>
                <b>{r.name || "A player"}</b>
                <small className="muted">
                  {r.username ? `@${r.username} · ` : ""}
                  <LocalTime iso={r.createdAt} style="relative" />
                </small>
              </span>
            </Link>
            <span className="composer-spacer" />
            <button type="button" className="btn btn-primary btn-small" disabled={busy === r.id} onClick={() => void answer(r.id, true)}>
              Accept
            </button>
            <button type="button" className="btn btn-small" disabled={busy === r.id} onClick={() => void answer(r.id, false)}>
              Decline
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
