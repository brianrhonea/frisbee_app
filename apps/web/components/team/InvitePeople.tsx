"use client";
import type { SearchPage } from "@stall10/shared";
import { useEffect, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";

/**
 * Find people by name and invite them to [teamId] (`POST
 * /v1/teams/:id/invites`); they accept from their Teams tab. For the
 * team's member managers, and a community's for the teams it links.
 */
export function InvitePeople({ teamId, teamName, onClose }: { teamId: string; teamName: string; onClose: () => void }) {
  const { user } = useAuth();
  const [q, setQ] = useState("");
  const [results, setResults] = useState<SearchPage["players"] | null>(null);
  const [invited, setInvited] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    const term = q.trim();
    if (!user || term.length < 2) {
      setResults(null);
      return;
    }
    let live = true;
    const timer = setTimeout(() => {
      callApi<SearchPage>(user, `/v1/public/search?q=${encodeURIComponent(term)}`)
        .then((page) => live && setResults(page.players.filter((p) => p.id !== user.uid)))
        .catch(() => live && setResults([]));
    }, 300);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [q, user]);

  async function invite(uid: string) {
    if (!user) return;
    setBusy(uid);
    setError("");
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/invites`, { method: "POST", body: { uid } });
      setInvited((m) => ({ ...m, [uid]: "Invited" }));
    } catch (e) {
      if (e instanceof ApiError && e.status === 409) setInvited((m) => ({ ...m, [uid]: "Already on it" }));
      else setError(e instanceof ApiError ? e.message : "Couldn't send the invite. Try again.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="card invite-panel" aria-label={`Invite people to ${teamName}`}>
      <div className="invite-head">
        <h2 className="card-title">Invite to {teamName}</h2>
        <button type="button" className="btn btn-small" onClick={onClose}>
          Done
        </button>
      </div>
      <input
        className="search-input"
        type="search"
        placeholder="Search people by name"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        aria-label="Search people by name"
        autoFocus
      />
      {error && <p className="form-error">{error}</p>}
      {results === null ? (
        <p className="muted small">They get an invite to accept from their Teams tab.</p>
      ) : results.length === 0 ? (
        <p className="muted small">No one by that name.</p>
      ) : (
        <ul className="invite-results">
          {results.map((p) => (
            <li key={p.id}>
              <span className="person">
                <Avatar name={p.name ?? "Player"} url={p.photoUrl} size={32} />
                <span>
                  {p.name ?? "Player"}
                  {p.username && <small className="muted"> @{p.username}</small>}
                </span>
              </span>
              {invited[p.id] ? (
                <span className="pill">{invited[p.id]}</span>
              ) : (
                <button type="button" className="btn btn-small btn-primary" disabled={busy !== null} onClick={() => void invite(p.id)}>
                  Invite
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
