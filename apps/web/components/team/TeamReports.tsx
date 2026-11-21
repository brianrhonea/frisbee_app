"use client";
import type { ReportInfo } from "@stall10/shared";
import { useCallback, useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { ReportCard } from "../ReportQueue";
import { useTeamHub } from "./TeamContext";

/**
 * Settings › Reports, for the team's admins and moderators: reports on its
 * chat, posts and their comments (Stall 10's staff see them too). Remove
 * takes the content down and closes every report on it; Dismiss closes
 * this one. Reporters stay anonymous here.
 */
export function TeamReports() {
  const { user } = useAuth();
  const { teamId } = useTeamHub();
  const [reports, setReports] = useState<ReportInfo[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const base = `/v1/teams/${encodeURIComponent(teamId)}/reports`;

  const load = useCallback(async () => {
    if (!user) return;
    try {
      setReports(await callApi<ReportInfo[]>(user, base));
    } catch (e) {
      setError(problem(e, "Couldn't load the reports."));
    }
  }, [user, base]);
  useEffect(() => {
    void load();
  }, [load]);

  async function act(r: ReportInfo, action: "remove" | "dismiss") {
    if (!user) return;
    if (action === "remove" && !window.confirm("Remove it for everyone? This can't be undone.")) return;
    setBusy(r.id);
    setError(null);
    try {
      await callApi(user, `${base}/${encodeURIComponent(r.id)}`, { method: "POST", body: { action } });
      await load();
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="card" id="reports">
      <h2 className="card-title">Reports</h2>
      <p className="muted small">What members reported in this team&apos;s chat and posts. Stall 10&apos;s staff see these reports too.</p>
      {error && <p className="form-error">{error}</p>}
      {reports === null ? (
        !error && <p className="muted">Loading…</p>
      ) : reports.length === 0 ? (
        <p className="empty">No open reports.</p>
      ) : (
        <ul className="report-list">
          {reports.map((r) => (
            <ReportCard
              key={r.id}
              report={r}
              actions={
                <>
                  <button type="button" className="btn btn-small" disabled={busy === r.id} onClick={() => void act(r, "dismiss")}>
                    Dismiss
                  </button>
                  <button type="button" className="btn btn-small btn-danger" disabled={busy === r.id} onClick={() => void act(r, "remove")}>
                    Remove
                  </button>
                </>
              }
            />
          ))}
        </ul>
      )}
    </section>
  );
}
