"use client";
import { useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { searchTagsFor, useMyProfile } from "./useMyProfile";

const sections = [
  ["stats", "Stats", "Your season totals and career table"],
  ["teams", "Teams", "The teams and groups you're on"],
  ["games", "Recent games", "Your lines from recent games"],
] as const;

/** A private profile, and which sections others see. Each switch saves at once. */
export function PrivacySettings() {
  const { user } = useAuth();
  const { profile, error: loadError } = useMyProfile();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (!user) return null;
  if (loadError) return <p className="form-error">{loadError}</p>;
  if (!profile) return <p className="muted">Loading…</p>;
  const me = user;
  const visibility = { stats: true, teams: true, games: true, ...profile.visibility };

  async function run(path: string, body: unknown) {
    setBusy(true);
    setError(null);
    try {
      await callApi(me, path, { method: "PUT", body });
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Couldn't save. Try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="stack">
      <div className="card">
        <h2 className="card-title">Account privacy</h2>
        <label className="switch-row">
          <span>
            <b>Private profile</b>
            <small className="muted">
              Only people you approve see your posts, stats and teams. Others see your name, username and photo.
            </small>
          </span>
          <input
            type="checkbox"
            role="switch"
            checked={profile.private === true}
            disabled={busy}
            onChange={(e) => void run("/v1/me/profile/privacy", { private: e.target.checked })}
          />
        </label>
      </div>
      <div className="card">
        <h2 className="card-title">Show on my profile</h2>
        {sections.map(([key, label, hint]) => (
          <label key={key} className="switch-row">
            <span>
              <b>{label}</b>
              <small className="muted">{hint}</small>
            </span>
            <input
              type="checkbox"
              role="switch"
              checked={visibility[key] !== false}
              disabled={busy}
              onChange={(e) =>
                void run("/v1/me/profile/visibility", {
                  visibility: { ...visibility, [key]: e.target.checked },
                  tags: searchTagsFor(profile),
                })
              }
            />
          </label>
        ))}
        <p className="muted small">Hidden sections come back the next time the app updates your profile.</p>
      </div>
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}
