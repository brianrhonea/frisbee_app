"use client";
import { chatAttachmentsMax, chatReactionChoices, chatTextMax } from "@stall10/shared";
import { type FormEvent, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { newId, photoProblem, uploadPhoto } from "@/lib/upload";
import { useAuth } from "./AuthProvider";

type Pending = { key: string; name: string; uploadId?: string; error?: string };

/**
 * The box under a chat thread: Enter sends, Shift+Enter starts a new line,
 * photos upload as they're picked (`chat` uploads for [upload.targetId],
 * with the new message's id as itemId). [path] is the room's or
 * conversation's messages endpoint.
 */
export function ChatComposer({
  path,
  upload,
  placeholder,
  replyTo,
  onClearReply,
}: {
  path: string;
  upload: { targetId: string };
  placeholder: string;
  replyTo?: { id: string; authorName?: string; text?: string } | null;
  onClearReply?: () => void;
}) {
  const { user } = useAuth();
  const [text, setText] = useState("");
  const [messageId, setMessageId] = useState(() => newId());
  const [files, setFiles] = useState<Pending[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);

  function addFiles(list: File[]) {
    if (!user) return;
    const room = chatAttachmentsMax - files.length;
    for (const file of list.slice(0, Math.max(0, room))) {
      const problem = photoProblem(file, "chat");
      if (problem) {
        setError(problem);
        continue;
      }
      const key = newId();
      setFiles((fs) => [...fs, { key, name: file.name }]);
      uploadPhoto(user, file, { purpose: "chat", targetId: upload.targetId, itemId: messageId }).then(
        (done) => setFiles((fs) => fs.map((f) => (f.key === key ? { ...f, uploadId: done.id } : f))),
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
    try {
      await callApi(user, path, {
        method: "POST",
        body: {
          id: messageId,
          text,
          uploadIds: ready.map((f) => f.uploadId!),
          ...(replyTo && { replyTo: replyTo.id }),
        },
      });
      setText("");
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
              📎 {f.name} {f.error ? `— ${f.error}` : f.uploadId ? "" : "(uploading…)"}{" "}
              <button type="button" className="text-btn" onClick={() => setFiles(files.filter((x) => x.key !== f.key))}>
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
      <div className="chat-input-row">
        <input ref={input} type="file" accept="image/*" multiple hidden onChange={(e) => addFiles([...(e.target.files ?? [])])} />
        <button type="button" className="icon-btn" aria-label="Attach a photo" onClick={() => input.current?.click()}>
          📎
        </button>
        <textarea
          aria-label={placeholder}
          placeholder={placeholder}
          rows={1}
          value={text}
          maxLength={chatTextMax}
          onChange={(e) => setText(e.target.value)}
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
}: {
  path: string;
  mine: string | null;
  canDelete: boolean;
  onReply?: () => void;
}) {
  const { user } = useAuth();
  const [picking, setPicking] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function call(url: string, method: "PUT" | "DELETE", body?: unknown) {
    if (!user) return;
    setError(null);
    try {
      await callApi(user, url, { method, body });
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
