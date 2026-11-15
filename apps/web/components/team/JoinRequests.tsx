"use client";
import { useState } from "react";
import { callApi, problem } from "@/lib/client";
import type { Doc, Live } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { ErrorNote, Loading } from "../StatusViews";

/** One person asking to join a group that approves members (teams/:id/joinRequests/:uid). */
export type JoinRequestDoc = Doc<{ name?: string }>;

/**
 * People asking to join a group that approves members, to approve or
 * decline (`POST …/join-requests/:uid/approve`, `DELETE …/join-requests/:uid`).
 * [requests] is the live list the invite provider already listens to.
 */
export function JoinRequests({ teamId, requests, card = true }: { teamId: string; requests: Live<JoinRequestDoc[]>; card?: boolean }) {
  const { user } = useAuth();
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const base = `/v1/teams/${encodeURIComponent(teamId)}/join-requests`;

  async function act(uid: string, path: string, method: string) {
    if (!user) return;
    setBusy(uid);
    setError(null);
    try {
      await callApi(user, path, { method });
    } catch (e) {
      setError(problem(e, "Couldn't do that. Try again."));
    } finally {
      setBusy(null);
    }
  }

  const body = requests.error ? (
    <ErrorNote>{requests.error}</ErrorNote>
  ) : !requests.data ? (
    <Loading />
  ) : requests.data.length === 0 ? (
    <p className="muted small">No one is waiting.</p>
  ) : (
    <ul className="people-list">
      {requests.data.map((r) => (
        <li key={r.id} className="person-row">
          <span className="person">
            <Avatar name={r.name || "Player"} size={32} />
            <span>{r.name || "Player"}</span>
          </span>
          <span className="post-admin">
            <button
              type="button"
              className="btn btn-small btn-primary"
              disabled={busy !== null}
              onClick={() => void act(r.id, `${base}/${encodeURIComponent(r.id)}/approve`, "POST")}
            >
              Approve
            </button>
            <button type="button" className="btn btn-small" disabled={busy !== null} onClick={() => void act(r.id, `${base}/${encodeURIComponent(r.id)}`, "DELETE")}>
              Decline
            </button>
          </span>
        </li>
      ))}
    </ul>
  );
  if (!card) {
    return (
      <div className="stack">
        {body}
        {error && <ErrorNote>{error}</ErrorNote>}
      </div>
    );
  }
  return (
    <section className="card">
      <h2 className="card-title">Asking to join</h2>
      {body}
      {error && <ErrorNote>{error}</ErrorNote>}
    </section>
  );
}
