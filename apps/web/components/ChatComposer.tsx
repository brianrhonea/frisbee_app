"use client";
import { insertMention, type MentionSuggestion } from "@stall10/shared";
import { type MentionContext, MentionMenu, suggestionsAt } from "./Mentions";
import { chatAttachmentsMax, chatQuickReactions, chatReactionGroups, chatTextMax, formatFileSize } from "@stall10/shared";
import { type FormEvent, type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";
import type { OutboxKind } from "@stall10/shared";
import { callApi } from "@/lib/client";
import { queuedNotice, submitOutbox } from "@/lib/outbox";
import { loadDraft, saveDraft } from "@/lib/drafts";
import { useVideoUploads } from "@/lib/metaFlags";
import { chatFileProblem, isVideoFile, newId, removeUpload, uploadPhoto, videoUploadsClosed } from "@/lib/upload";
import { useAuth } from "./AuthProvider";
import { useConfirm } from "@/components/ui/ConfirmDialog";

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
  onShareEvent,
  onCreatePoll,
  mentions,
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
  /** "Share an event" beside files in the attach menu (team rooms, F3). */
  onShareEvent?: () => void;
  /** "Poll" in the attach menu (team rooms, F33). Without either, there's no menu. */
  onCreatePoll?: () => void;
  /** Team chat: suggest @mentions while typing (Mentions.tsx). */
  mentions?: MentionContext;
}) {
  const { user } = useAuth();
  // Video is offered only while meta/flags.videoUploads is true (closed when unread).
  const videoOpen = useVideoUploads();
  const [text, setText] = useState("");
  const [messageId, setMessageId] = useState(() => newId());
  const [files, setFiles] = useState<Pending[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [attachMenu, setAttachMenu] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const box = useRef<HTMLTextAreaElement>(null);
  const [cursor, setCursor] = useState(0);
  const [active, setActive] = useState(0);
  const suggest = suggestionsAt(text, cursor, mentions);
  function pick(o: MentionSuggestion) {
    if (!suggest) return;
    const next = insertMention(text, suggest.start, cursor, o.label);
    edit(next.text);
    setCursor(next.cursor);
    setActive(0);
    requestAnimationFrame(() => {
      box.current?.focus();
      box.current?.setSelectionRange(next.cursor, next.cursor);
    });
  }
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
      const problem = !videoOpen && isVideoFile(file) ? videoUploadsClosed : chatFileProblem(file);
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
      {suggest && <MentionMenu options={suggest.options} active={Math.min(active, suggest.options.length - 1)} onPick={pick} />}
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
        {onShareEvent || onCreatePoll ? (
          <span className="attach-menu">
            <button
              type="button"
              className="icon-btn"
              aria-label="Attach"
              aria-haspopup="menu"
              aria-expanded={attachMenu}
              title={onShareEvent ? "Attach files, share an event or ask a poll" : "Attach files or ask a poll"}
              onClick={() => setAttachMenu(!attachMenu)}
            >
              📎
            </button>
            {attachMenu && (
              <span className="attach-menu-list" role="menu">
                <button
                  type="button"
                  role="menuitem"
                  onClick={() => {
                    setAttachMenu(false);
                    input.current?.click();
                  }}
                >
                  {videoOpen ? "Photo, video or file" : "Photo or file"}
                </button>
                {onShareEvent && (
                  <button
                    type="button"
                    role="menuitem"
                    onClick={() => {
                      setAttachMenu(false);
                      onShareEvent();
                    }}
                  >
                    Share an event
                  </button>
                )}
                {onCreatePoll && (
                  <button
                    type="button"
                    role="menuitem"
                    onClick={() => {
                      setAttachMenu(false);
                      onCreatePoll();
                    }}
                  >
                    Poll
                  </button>
                )}
              </span>
            )}
          </span>
        ) : (
          <button type="button" className="icon-btn" aria-label="Attach files" title={videoOpen ? "Attach photos, videos or files" : "Attach photos or files"} onClick={() => input.current?.click()}>
            📎
          </button>
        )}
        <textarea
          ref={box}
          aria-label={placeholder}
          placeholder={placeholder}
          rows={1}
          value={text}
          maxLength={chatTextMax}
          onChange={(e) => {
            edit(e.target.value);
            setCursor(e.target.selectionStart ?? e.target.value.length);
            setActive(0);
            onTyping?.(e.target.value.trim().length > 0);
          }}
          onSelect={(e) => setCursor(e.currentTarget.selectionStart ?? 0)}
          onBlur={() => onTyping?.(false)}
          onPaste={(e) => {
            const pasted = [...e.clipboardData.files];
            if (pasted.length) addFiles(pasted);
          }}
          onKeyDown={(e) => {
            // While @mentions are suggested: arrows move, Enter or Tab picks, Escape closes.
            if (suggest) {
              const n = suggest.options.length;
              if (e.key === "ArrowDown" || e.key === "ArrowUp") {
                e.preventDefault();
                setActive((a) => (a + (e.key === "ArrowDown" ? 1 : n - 1)) % n);
                return;
              }
              if (e.key === "Enter" || e.key === "Tab") {
                e.preventDefault();
                pick(suggest.options[Math.min(active, n - 1)]);
                return;
              }
              if (e.key === "Escape") {
                e.preventDefault();
                setCursor(-1);
                return;
              }
            }
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

/**
 * Reply, react and delete on one message; [path] is the message's endpoint.
 * Reacting opens a bubble of quick reactions above the message with a +
 * for any other emoji (as the app's double-tap); the list opens it on a
 * double-click too, through [picking] and [onPickingChange].
 */
export function MessageActions({
  path,
  mine,
  canDelete,
  onReply,
  onDeleted,
  extra,
  picking: pickingProp,
  onPickingChange,
}: {
  path: string;
  mine: string | null;
  canDelete: boolean;
  onReply?: () => void;
  /** More actions before Delete, e.g. a team room's Pin (F2). */
  extra?: ReactNode;
  /** Told once the message is deleted (older pages aren't live). */
  onDeleted?: () => void;
  /** Whether the reaction bubble is open, when the list controls it. */
  picking?: boolean;
  onPickingChange?: (open: boolean) => void;
}) {
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const [pickingOwn, setPickingOwn] = useState(false);
  const picking = pickingProp ?? pickingOwn;
  const setPicking = (open: boolean) => (onPickingChange ? onPickingChange(open) : setPickingOwn(open));
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
      <button type="button" className="text-btn" data-reaction-toggle aria-expanded={picking} onClick={() => setPicking(!picking)} aria-label="React">
        {mine ?? "☺"}
      </button>
      {picking && (
        <ReactionBubble
          mine={mine}
          onClose={() => setPicking(false)}
          onPick={(e) => {
            setPicking(false);
            void call(`${path}/reaction`, "PUT", { emoji: mine === e ? null : e });
          }}
        />
      )}
      {extra}
      {canDelete && (
        <button
          type="button"
          className="text-btn danger"
          onClick={async () => {
            if ((await askConfirm({ message: "Delete this message?", confirmLabel: "Delete", destructive: true }))) void call(path, "DELETE");
          }}
        >
          Delete
        </button>
      )}
      {error && <span className="form-error">{error}</span>}
    </div>
  );
}

/** The quick reactions in a pill over the message, then + for every emoji. Escape or a click outside closes it. */
function ReactionBubble({ mine, onPick, onClose }: { mine: string | null; onPick: (emoji: string) => void; onClose: () => void }) {
  const [more, setMore] = useState(false);
  // Under the message when there's no room above it inside the message
  // list (the first message): above, the list's edge and the chat header
  // would cover it.
  const [below, setBelow] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const el = ref.current;
    const message = el?.offsetParent;
    if (!el || !message) return;
    let clipTop = 0;
    for (let n = message.parentElement; n; n = n.parentElement) {
      if (/(auto|scroll|hidden)/.test(getComputedStyle(n).overflowY)) {
        clipTop = Math.max(clipTop, n.getBoundingClientRect().top);
        break;
      }
    }
    setBelow(message.getBoundingClientRect().top - clipTop < el.getBoundingClientRect().height + 4);
  }, [more]);
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    ref.current?.querySelector("button")?.focus();
    const key = (e: KeyboardEvent) => e.key === "Escape" && close.current();
    const click = (e: MouseEvent) => {
      const t = e.target as Element;
      // The React button toggles it itself.
      if (ref.current && !ref.current.contains(t) && !t.closest?.("[data-reaction-toggle]")) close.current();
    };
    document.addEventListener("keydown", key);
    document.addEventListener("mousedown", click);
    return () => {
      document.removeEventListener("keydown", key);
      document.removeEventListener("mousedown", click);
    };
  }, []);
  const other = mine && !(chatQuickReactions as readonly string[]).includes(mine) ? mine : null;
  return (
    <div className={below ? "reaction-bubble below" : "reaction-bubble"} ref={ref} role="dialog" aria-label="React to this message">
      <div className="reaction-quick" role="group" aria-label="Quick reactions">
        {chatQuickReactions.map((e) => (
          <button key={e} type="button" className={mine === e ? "on" : ""} aria-pressed={mine === e} aria-label={`React ${e}`} onClick={() => onPick(e)}>
            {e}
          </button>
        ))}
        {other && (
          <button type="button" className="on" aria-pressed aria-label={`React ${other}`} onClick={() => onPick(other)}>
            {other}
          </button>
        )}
        <button type="button" className="reaction-more" aria-expanded={more} aria-label="More emoji" onClick={() => setMore(!more)}>
          +
        </button>
      </div>
      {more && (
        <div className="reaction-all">
          {chatReactionGroups.map((g) => (
            <section key={g.name} aria-label={g.name}>
              <h4>{g.name}</h4>
              <div className="reaction-grid">
                {g.emoji.map((e) => (
                  <button key={e} type="button" className={mine === e ? "on" : ""} aria-label={`React ${e}`} onClick={() => onPick(e)}>
                    {e}
                  </button>
                ))}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
