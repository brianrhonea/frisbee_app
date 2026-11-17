"use client";
import type { OutboxKind } from "@stall10/shared";
import { outboxStateText, useOutboxFor } from "@/lib/outbox";

/**
 * The member's messages still waiting to go out (sent while Stall 10
 * couldn't be reached), at the end of the thread until the real one
 * arrives with the same id. As the app's thread shows them.
 */
export function PendingMessages({ kind, target, shown }: { kind: OutboxKind; target: string; shown: { id: string }[] }) {
  const pending = useOutboxFor(kind, target);
  const there = new Set(shown.map((m) => m.id));
  const left = pending.filter((j) => !there.has(j.id));
  if (left.length === 0) return null;
  return (
    <>
      {left.map((j) => (
        <div key={j.id} className="message mine message-pending">
          <div className="message-main">
            {j.replyTo && (
              <p className="message-reply">
                ↪ {j.replyTo.authorName}: {j.replyTo.text}
              </p>
            )}
            {j.preview && <p className="message-text">{j.preview}</p>}
            {j.files > 0 && <p className="muted small">📎 {j.files === 1 ? "1 attachment" : `${j.files} attachments`}</p>}
            <p className={`small ${j.state === "failed" ? "form-error" : "muted"}`}>
              {j.state === "failed" ? `Not sent: ${outboxStateText(j)} Review it in "Waiting to send".` : outboxStateText(j)}
            </p>
          </div>
        </div>
      ))}
    </>
  );
}
