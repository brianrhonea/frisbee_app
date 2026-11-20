"use client";
import { type DataExport, dataExportFileName, downloadDataDescription } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useState } from "react";
import { callApi } from "@/lib/client";

/**
 * Settings → Account → Your data (download_data_group.dart in the app):
 * fetches `GET /v1/me/export` and saves it as a JSON file. The API allows
 * one every 10 minutes and says so when it's too soon.
 */
export function DownloadData({ user }: { user: User }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function download() {
    setBusy(true);
    setError("");
    try {
      const data = await callApi<DataExport>(user, "/v1/me/export");
      const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }));
      const a = document.createElement("a");
      a.href = url;
      a.download = dataExportFileName(new Date(data.exportedAt));
      document.body.appendChild(a);
      a.click();
      a.remove();
      // After the click has started the download.
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card">
      <h2 className="card-title">Your data</h2>
      <p className="muted small">{downloadDataDescription}</p>
      <div className="form-actions">
        {error && (
          <span className="form-error" role="alert">
            {error}
          </span>
        )}
        <button className="btn" type="button" disabled={busy} onClick={() => void download()}>
          {busy ? "Preparing your data…" : "Download your data"}
        </button>
      </div>
    </div>
  );
}
