"use client";
import { chatAttachmentsMax, chatReactionChoices, chatTextMax, formatFileSize } from "@stall10/shared";
import { type FormEvent, useEffect, useRef, useState } from "react";
import type { OutboxKind } from "@stall10/shared";
import { callApi } from "@/lib/client";
import { queuedNotice, submitOutbox } from "@/lib/outbox";
import { loadDraft, saveDraft } from "@/lib/drafts";
import { chatFileProblem, newId, removeUpload, uploadPhoto } from "@/lib/upload";
import { useAuth } from "./AuthProvider";

type Pending = { key: string; name: string; size: number; uploadId?: string; error?: string };

/**
 * The box under a chat thread: Enter sends, Shift+Enter starts a new line,
 * files (any kind, as in the app: photos, videos, documents) upload as they're picked (`chat` uploads for [upload.targetId],
 * with the new message's id as itemId). [path] is the room's or
 * conversation's messages endpoint. With a [draftKey], unsent text is kept
 * in this browser until it's sent, as the app keeps drafts per thread.
 */
export function ChatComposer({
  path,
  upload,
  placeholder,
  replyTo,
  onClearReply,
  onTyping,
  draftKey,
  outbox,
}: {
  path: string;
  /** Where this thread's messages wait while Stall 10 can't be reached (the app's OutboxKind and target). */
  outbox: { kind: OutboxKind; target: string };
  upload: { targetId: string };
  placeholder: string;
  replyTo?: { id: string; authorName?: string; text?: string } | null;
  onClearReply?: () => void;
  /** Told when the member has words in the box and when they've cleared or sent them. */
  onTyping?: (typing: boolean) => void;
  /** Where this thread's unsent text is kept (`dm_<id>`, `chat_<team>_<room>`). */
  draftKey?: string;
}) {
  const { user } = useAuth();
  const [text, setText] = useState("");
  const [messageId, setMessageId] = useState(() => newId());
  const [files, setFiles] = useState<Pending[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);
  /** Files removed while still uploading: deleted once their upload finishes. */
  const dropped = useRef(new Set<string>());
  const uid = user?.uid;

  // What this member left unsent here last time (read after mounting: it's in this browser only).
  useEffect(() => {
    if (draftKey && uid) setText(loadDraft(uid, draftKey));
  }, [draftKey, uid]);

  function edit(value: string) {
    setText(value);
    if (draftKey && uid) saveDraft(uid, draftKey, value);
  }

  // Remove: the file isn't sent, and the API deletes what it stored (as soon as it has it).
  function removeFile(f: Pending) {
    setFiles((fs) => fs.filter((x) => x.key !== f.key));
    if (!user) return;
    if (f.uploadId) void removeUpload(user, f.uploadId);
    else if (!f.error) dropped.current.add(f.key);
  }

  function addFiles(list: File[]) {
    if (!user) return;
    const room = chatAttachmentsMax - files.length;
    for (const file of list.slice(0, Math.max(0, room))) {
      const problem = chatFileProblem(file);
      if (problem) {
        setError(problem);
        continue;
      }
      const key = newId();
      setFiles((fs) => [...fs, { key, name: file.name, size: file.size }]);
      uploadPhoto(user, file, { purpose: "chat", targetId: upload.targetId, itemId: messageId }).then(
        (done) => {
          if (dropped.current.delete(key)) return void removeUpload(user, done.id);
          setFiles((fs) => fs.map((f) => (f.key === key ? { ...f, uploadId: done.id } : f)));
        },
        (e: Error) => setFiles((fs) => fs.map((f) => (f.key === key ? { ...f, error: e.message } : f))),
      );
    }
  }

  const uploading = files.some((f) => !f.uploadId && !f.error);
  const ready = files.filter((f) => f.uploadId);
  const canSend = !busy && !uploading && (text.trim().length > 0 || ready.length > 0);

  async function send(e?: FormEvent) {
    e?.preventDefault();
    if (!user || !canSend) return;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const done = await submitOutbox(user, {
        kind: outbox.kind,
        id: messageId,
        target: outbox.target,
        label: "Message",
        path,
        body: {
          text,
          uploadIds: ready.map((f) => f.uploadId!),
          ...(replyTo && { replyTo: replyTo.id }),
        },
        preview: text.trim(),
        files: ready.length,
        replyTo: replyTo ? { authorName: replyTo.authorName, text: replyTo.text } : null,
      });
      if (done === "queued") setNotice(queuedNotice("Message"));
      edit("");
      onTyping?.(false);
      setFiles([]);
      setMessageId(newId());
      onClearReply?.();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className="thread-foot chat-composer" onSubmit={(e) => void send(e)}>
      {replyTo && (
        <p className="message-reply">
          ↪ Replying to {replyTo.authorName || "a message"}: {(replyTo.text ?? "").slice(0, 80)}{" "}
          <button type="button" className="text-btn" onClick={onClearReply}>
            Cancel
          </button>
        </p>
      )}
      {files.length > 0 && (
        <ul className="chat-files">
          {files.map((f) => (
            <li key={f.key} className={f.error ? "failed" : ""}>
              📎 {f.name} <small className="muted">{formatFileSize(f.size)}</small> {f.error ? `— ${f.error}` : f.uploadId ? "" : "(uploading…)"}{" "}
              <button type="button" className="text-btn" onClick={() => removeFile(f)}>
                Remove
              </button>
            </li>
          ))}
        </ul>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {notice && (
        <p className="muted small" role="status">
          {notice}
        </p>
      )}
      <div className="chat-input-row">
        <input
          ref={input}
          type="file"
          multiple
          hidden
          onChange={(e) => {
            addFiles([...(e.target.files ?? [])]);
            e.target.value = "";
          }}
        />
        <button type="button" className="icon-btn" aria-label="Attach files" title="Attach photos, videos or files" onClick={() => input.current?.click()}>
          📎
        </button>
        <textarea
          aria-label={placeholder}
          placeholder={placeholder}
          rows={1}
          value={text}
          maxLength={chatTextMax}
          onChange={(e) => {
            edit(e.target.value);
            onTyping?.(e.target.value.trim().length > 0);
          }}
          onBlur={() => onTyping?.(false)}
          onPaste={(e) => {
            const pasted = [...e.clipboardData.files];
            if (pasted.length) addFiles(pasted);
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              void send();
            }
            if (e.key === "Escape") onClearReply?.();
          }}
        />
        <button type="submit" className="btn btn-primary btn-small" disabled={!canSend}>
          Send
        </button>
      </div>
    </form>
  );
}

/** Reply, react and delete on one message; [path] is the message's endpoint. */
export function MessageActions({
  path,
  mine,
  canDelete,
  onReply,
  onDeleted,
}: {
  path: string;
  mine: string | null;
  canDelete: boolean;
  onReply?: () => void;
  /** Told once the message is deleted (older pages aren't live). */
  onDeleted?: () => void;
}) {
  const { user } = useAuth();
  const [picking, setPicking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function call(url: string, method: "PUT" | "DELETE", body?: unknown) {
    if (!user) return;
    setError(null);
    try {
      await callApi(user, url, { method, body });
      if (method === "DELETE") onDeleted?.();
    } catch (e) {
      setError((e as Error).message);
    }
  }

  return (
    <div className="message-actions">
      {onReply && (
        <button type="button" className="text-btn" onClick={onReply} aria-label="Reply">
          Reply
        </button>
      )}
      <button type="button" className="text-btn" aria-expanded={picking} onClick={() => setPicking(!picking)} aria-label="React">
        {mine ?? "☺"}
      </button>
      {picking && (
        <span className="reaction-picker" role="group" aria-label="Pick a reaction">
          {chatReactionChoices.map((e) => (
            <button
              key={e}
              type="button"
              className={mine === e ? "on" : ""}
              onClick={() => {
                setPicking(false);
                void call(`${path}/reaction`, "PUT", { emoji: mine === e ? null : e });
              }}
            >
              {e}
            </button>
          ))}
        </span>
      )}
      {canDelete && (
        <button
          type="button"
          className="text-btn danger"
          onClick={() => {
            if (window.confirm("Delete this message?")) void call(path, "DELETE");
          }}
        >
          Delete
        </button>
      )}
      {error && <span className="form-error">{error}</span>}
    </div>
  );
}
