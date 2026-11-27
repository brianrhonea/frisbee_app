"use client";
import { meetingLimits } from "@stall10/shared";
import { type FormEvent, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { usePagedMessages, useThreadScroll } from "@/lib/messages";
import { useAuth } from "../../AuthProvider";
import { LocalTime } from "../../LocalTime";
import { loadAtTop, OlderMessages } from "../../OlderMessages";
import { meetingApi } from "./model";
import { useConfirm } from "@/components/ui/ConfirmDialog";

interface Message {
  authorId?: string;
  authorName?: string;
  text?: string;
  createdAt?: string;
}

/** Messages per page, live and older (MessageThreadViewModel.pageSize). */
const pageSize = 50;

/**
 * The chat inside the call (MeetingChatViewModel): text only, for people in
 * the call. Authors delete their own; admins any.
 */
export function MeetingChat({ teamId, meetingId, canModerate }: { teamId: string; meetingId: string; canModerate: boolean }) {
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const messages = usePagedMessages<Message>(`teams/${teamId}/meetings/${meetingId}/messages`, pageSize);
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const body = useRef<HTMLDivElement>(null);
  const list = messages.list ?? [];
  useThreadScroll(body, list[0]?.id, list[list.length - 1]?.id);

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
      <div className="call-chat-body" ref={body} aria-live="polite" onScroll={loadAtTop(messages)}>
        <OlderMessages paged={messages} />
        {messages.error ? (
          <p className="form-error">{messages.error}</p>
        ) : !messages.list ? (
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
                    onClick={async () => {
                      if (user && (await askConfirm({ message: "Delete this message?", confirmLabel: "Delete", destructive: true }))) {
                        void callApi(user, `${meetingApi(teamId, meetingId)}/messages/${encodeURIComponent(m.id)}`, { method: "DELETE" }).then(
                          () => messages.removed(m.id),
                          (err: Error) => setError(err.message),
                        );
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
