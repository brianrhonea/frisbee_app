"use client";
import { type NotificationCategory, notificationCategories, notificationCategoryInfo } from "@stall10/shared";
import { useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { useMyTeams } from "../useMyTeams";

/** users/{uid}/settings/notifications (NotificationPreferences in the app). */
interface Prefs {
  categories?: Partial<Record<NotificationCategory, boolean>>;
  teams?: Record<string, Partial<Record<NotificationCategory, boolean>>>;
  mutedRooms?: string[];
}

const perTeam = notificationCategories.filter((c) => notificationCategoryInfo[c].perTeam);

/**
 * What to be notified about, for every team and per team, as the app's
 * notification settings. On the website notices land in Notifications;
 * the app also pushes them to the phone.
 */
export function NotificationSettings() {
  const { user } = useAuth();
  const prefs = useLiveDoc<Prefs>(user ? `users/${user.uid}/settings/notifications` : null);
  const teams = useMyTeams<{ name?: string }>(user?.uid);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [open, setOpen] = useState<string | null>(null);

  if (!user) return null;
  if (prefs.error) return <p className="form-error">Couldn&apos;t load your settings. Try again.</p>;
  if (prefs.data === undefined) return <p className="muted">Loading…</p>;
  const me = user;
  const p: Prefs = prefs.data ?? {};
  const isOn = (c: NotificationCategory) => p.categories?.[c] ?? true;
  const isOnFor = (c: NotificationCategory, teamId: string) => p.teams?.[teamId]?.[c] ?? isOn(c);
  const custom = (teamId: string) => Object.keys(p.teams?.[teamId] ?? {}).length > 0;

  async function run(method: "PUT" | "DELETE", path: string, body?: object) {
    setBusy(true);
    setError("");
    try {
      await callApi(me, path, { method, ...(body && { body }) });
    } catch (e) {
      setError(problem(e, "Couldn't save. Try again."));
    } finally {
      setBusy(false);
    }
  }
  const setCategory = (category: NotificationCategory, on: boolean, teamId?: string) =>
    void run("PUT", "/v1/me/notification-settings/category", { category, on, ...(teamId && { teamId }) });

  const myTeams = [...(teams.data ?? [])].sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""));
  return (
    <div className="stack">
      <div className="card">
        <h2 className="card-title">Notify me about</h2>
        <p className="muted small">
          Notices show in Notifications here and in the app, and the app also sends them to your phone. Muted chats stay
          quiet everywhere.
        </p>
        {notificationCategories.map((c) => (
          <label className="switch-row" key={c}>
            <span>
              <b>{notificationCategoryInfo[c].label}</b>
              <small className="muted">{notificationCategoryInfo[c].description}</small>
            </span>
            <input type="checkbox" role="switch" checked={isOn(c)} disabled={busy} onChange={(e) => setCategory(c, e.target.checked)} />
          </label>
        ))}
      </div>

      {myTeams.length > 0 && (
        <div className="card">
          <h2 className="card-title">For each team</h2>
          <p className="muted small">Teams use the settings above unless you change them here.</p>
          <ul className="notify-teams">
            {myTeams.map((t) => {
              const shown = open === t.id;
              return (
                <li key={t.id}>
                  <button type="button" className="notify-team-head" aria-expanded={shown} onClick={() => setOpen(shown ? null : t.id)}>
                    <b>{t.name ?? "Team"}</b>
                    <small className="muted">{custom(t.id) ? "Custom for this team" : "Using your defaults"}</small>
                  </button>
                  {shown && (
                    <div className="notify-team-body">
                      {perTeam.map((c) => (
                        <label className="switch-row" key={c}>
                          <span>
                            <b>{notificationCategoryInfo[c].label}</b>
                          </span>
                          <input
                            type="checkbox"
                            role="switch"
                            checked={isOnFor(c, t.id)}
                            disabled={busy}
                            onChange={(e) => setCategory(c, e.target.checked, t.id)}
                          />
                        </label>
                      ))}
                      {custom(t.id) && (
                        <button
                          type="button"
                          className="btn btn-small"
                          disabled={busy}
                          onClick={() => void run("DELETE", `/v1/me/notification-settings/teams/${encodeURIComponent(t.id)}`)}
                        >
                          Use my defaults
                        </button>
                      )}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        </div>
      )}
      {error && <p className="form-error" role="alert">{error}</p>}
    </div>
  );
}
