"use client";
import { useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "../AuthProvider";

/** Whether others see "Seen" when the member has read their messages (users/{uid}.readReceipts). */
export function ReadReceiptsSetting() {
  const { user } = useAuth();
  const doc = useLiveDoc<{ readReceipts?: boolean }>(user ? `users/${user.uid}` : null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  if (!user || doc.data === undefined) return null;
  const me = user;
  const on = doc.data?.readReceipts !== false;
  async function set(next: boolean) {
    setBusy(true);
    setError("");
    try {
      await callApi(me, "/v1/me/read-receipts", { method: "PUT", body: { on: next } });
    } catch (e) {
      setError(problem(e, "Couldn't save. Try again."));
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="card">
      <label className="switch-row">
        <span>
          <b>Read receipts</b>
          <small className="muted">Let people see when you&apos;ve read their messages.</small>
        </span>
        <input type="checkbox" role="switch" checked={on} disabled={busy} onChange={(e) => void set(e.target.checked)} />
      </label>
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}
