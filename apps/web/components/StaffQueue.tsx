"use client";
import type { ModerationAccess, ReportInfo, StaffAction } from "@stall10/shared";
import { useCallback, useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useAuth } from "./AuthProvider";
import { ReportCard } from "./ReportQueue";
import { useConfirm } from "@/components/ui/ConfirmDialog";

const confirms: Partial<Record<StaffAction, string>> = {
  remove: "Remove it for everyone? Every open report on it closes.",
  suspend: "Suspend this account? They're signed out and can't sign in, post or message until you lift it.",
  warn: "Send them a warning notification?",
};

/**
 * Every open report, newest first, for Stall 10's staff (App Store
 * guideline 1.2): remove the content, dismiss the report, warn the author,
 * or suspend their account (and lift it). A staff tool, on the website only.
 */
export function StaffQueue() {
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const [staff, setStaff] = useState<boolean | null>(null);
  const [reports, setReports] = useState<ReportInfo[] | null>(null);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    try {
      const access = await callApi<ModerationAccess>(user, "/v1/me/moderation");
      setStaff(access.staff);
      if (access.staff) setReports((await callApi<{ reports: ReportInfo[] }>(user, "/v1/staff/reports")).reports);
    } catch (e) {
      setError(problem(e, "Couldn't load the reports."));
    }
  }, [user]);
  useEffect(() => {
    void load();
  }, [load]);

  async function act(r: ReportInfo, action: StaffAction) {
    if (!user) return;
    const ask = confirms[action];
    if (ask && !(await askConfirm(ask))) return;
    setBusy(r.id);
    setError(null);
    try {
      const note = notes[r.id]?.trim();
      await callApi(user, `/v1/staff/reports/${encodeURIComponent(r.id)}`, { method: "POST", body: { action, ...(note && { note }) } });
      await load();
    } catch (e) {
      setError(problem(e));
    } finally {
      setBusy(null);
    }
  }

  if (staff === false) return <p className="empty">This page is for Stall 10&apos;s staff.</p>;
  return (
    <div className="stack">
      {error && <p className="form-error">{error}</p>}
      {reports === null ? (
        !error && <p className="muted">Loading…</p>
      ) : reports.length === 0 ? (
        <p className="empty">No open reports.</p>
      ) : (
        <ul className="report-list card">
          {reports.map((r) => (
            <ReportCard
              key={r.id}
              report={r}
              actions={
                <>
                  <input
                    className="report-note"
                    placeholder="Note (optional)"
                    maxLength={500}
                    value={notes[r.id] ?? ""}
                    onChange={(e) => setNotes({ ...notes, [r.id]: e.target.value })}
                  />
                  <button type="button" className="btn btn-small" disabled={busy === r.id} onClick={() => void act(r, "dismiss")}>
                    Dismiss
                  </button>
                  <button type="button" className="btn btn-small" disabled={busy === r.id} onClick={() => void act(r, "warn")}>
                    Warn
                  </button>
                  <button
                    type="button"
                    className="btn btn-small"
                    disabled={busy === r.id}
                    onClick={() => void act(r, r.authorSuspended ? "unsuspend" : "suspend")}
                  >
                    {r.authorSuspended ? "Lift suspension" : "Suspend"}
                  </button>
                  {r.target.kind !== "user" && (
                    <button type="button" className="btn btn-small btn-danger" disabled={busy === r.id} onClick={() => void act(r, "remove")}>
                      Remove
                    </button>
                  )}
                </>
              }
            />
          ))}
        </ul>
      )}
    </div>
  );
}
