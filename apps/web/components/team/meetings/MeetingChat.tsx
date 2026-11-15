"use client";
import { meetingLimits } from "@stall10/shared";
import { limit, orderBy } from "firebase/firestore";
import { type FormEvent, useEffect, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { useLiveQuery } from "@/lib/live";
import { useAuth } from "../../AuthProvider";
import { LocalTime } from "../../LocalTime";
import { meetingApi } from "./model";

interface Message {
  authorId?: string;
  authorName?: string;
  text?: string;
  createdAt?: string;
}

const shown = 100;

/**
 * The chat inside the call (MeetingChatViewModel): text only, for people in
 * the call. Authors delete their own; admins any.
 */
export function MeetingChat({ teamId, meetingId, canModerate }: { teamId: string; meetingId: string; canModerate: boolean }) {
  const { user } = useAuth();
  const messages = useLiveQuery<Message>(`teams/${teamId}/meetings/${meetingId}/messages`, [orderBy("createdAt", "desc"), limit(shown)], meetingId);
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const body = useRef<HTMLDivElement>(null);
  const list = (messages.data ?? []).slice().reverse();
  useEffect(() => {
    if (body.current) body.current.scrollTop = body.current.scrollHeight;
  }, [list.length]);

  async function send(e: FormEvent) {
    e.preventDefault();
    if (!user || !text.trim()) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `${meetingApi(teamId, meetingId)}/messages`, { method: "POST", body: { text: text.trim() } });
      setText("");
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="call-chat">
      <div className="call-chat-body" ref={body} aria-live="polite">
        {messages.error ? (
          <p className="form-error">{messages.error}</p>
        ) : !messages.data ? (
          <p className="muted small">Loading…</p>
        ) : list.length === 0 ? (
          <p className="muted small">No messages yet. Only people in the call see this chat.</p>
        ) : (
          list.map((m) => (
            <div key={m.id} className="call-chat-message">
              <p className="small">
                <b>{m.authorName || "Member"}</b> <LocalTime iso={m.createdAt} style="relative" />
                {(m.authorId === user?.uid || canModerate) && (
                  <button
                    type="button"
                    className="text-btn"
                    onClick={() => {
                      if (user && window.confirm("Delete this message?")) {
                        void callApi(user, `${meetingApi(teamId, meetingId)}/messages/${encodeURIComponent(m.id)}`, { method: "DELETE" }).catch((err: Error) => setError(err.message));
                      }
                    }}
                  >
                    Delete
                  </button>
                )}
              </p>
              <p className="message-text">{m.text}</p>
            </div>
          ))
        )}
      </div>
      <form className="call-chat-form" onSubmit={(e) => void send(e)}>
        <input aria-label="Message" placeholder="Message everyone" value={text} maxLength={meetingLimits.message} onChange={(e) => setText(e.target.value)} />
        <button type="submit" className="btn btn-small btn-primary" disabled={busy || !text.trim()}>
          Send
        </button>
      </form>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
