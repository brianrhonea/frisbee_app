"use client";
import { useState } from "react";
import { discardOutbox, outboxStateText, retryOutbox, useOutbox } from "@/lib/outbox";
import { useOnline } from "@/lib/online";

/**
 * A strip at the top while Stall 10 can't be reached, or while anything
 * waits to send or was turned down; it opens the "Waiting to send" list
 * (Try again, Discard). As the app's OfflineBanner.
 */
export function OfflineBanner() {
  const online = useOnline();
  const jobs = useOutbox();
  const [open, setOpen] = useState(false);
  const failed = jobs.filter((j) => j.state === "failed").length;
  const waiting = jobs.length - failed;
  if (online && jobs.length === 0) return null;
  const things = waiting === 1 ? "1 item" : `${waiting} items`;
  const text = !online
    ? waiting === 0
      ? "You're offline. What you send will go out when you're back."
      : `You're offline. ${things} will send when you're back.`
    : waiting > 0
      ? `Sending ${things}…`
      : failed === 1
        ? "1 item couldn't be sent."
        : `${failed} items couldn't be sent.`;
  return (
    <div className={`offline-banner${online && waiting === 0 ? " failed" : ""}`} role="status">
      <p>
        <span>{text}</span>
        {jobs.length > 0 && (
          <button type="button" className="text-btn" aria-expanded={open} onClick={() => setOpen(!open)}>
            {open ? "Hide" : "Waiting to send"}
          </button>
        )}
      </p>
      {open && jobs.length > 0 && (
        <ul className="outbox-list">
          {jobs.map((j) => (
            <li key={j.id}>
              <div>
                <b>{j.label}</b>
                {j.preview && <span className="outbox-preview">: {j.preview}</span>}
                <small className={j.state === "failed" ? "form-error" : "muted"}>
                  {outboxStateText(j)}
                  {j.files > 0 && ` · ${j.files === 1 ? "1 attachment" : `${j.files} attachments`}`}
                </small>
              </div>
              {j.state !== "sending" && (
                <span className="outbox-actions">
                  {j.state === "failed" && (
                    <button type="button" className="text-btn" onClick={() => void retryOutbox(j.id)}>
                      Try again
                    </button>
                  )}
                  <button type="button" className="text-btn danger" onClick={() => void discardOutbox(j.id)}>
                    Discard
                  </button>
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
