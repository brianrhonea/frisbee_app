"use client";
import { groupSizeMax, type GroupAddedResult, type OpenConversationResult } from "@stall10/shared";
import { limit, orderBy, where } from "firebase/firestore";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { type FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { ChatComposer, MessageActions } from "./ChatComposer";
import { LocalTime } from "./LocalTime";
import { MemberImage } from "./MemberImage";
import { type PickedPerson, PersonPicker } from "./PersonPicker";

/** conversations/{id} (Conversation in the app). */
interface Conversation {
  kind?: "direct" | "group";
  name?: string;
  createdBy?: string;
  participants?: string[];
  names?: Record<string, string>;
  lastMessage?: string;
  lastMessageAt?: string | null;
  lastSenderId?: string;
  readAt?: Record<string, string>;
  status?: "accepted" | "request" | "declined";
  requestedOf?: string;
}
/** users/{uid}/dmReads/{id}: the member's own read time, archive and clear. */
interface Mine {
  readAt?: string;
  archivedAt?: string;
  clearedAt?: string;
}
interface Message {
  authorId?: string;
  authorName?: string;
  text?: string;
  attachments?: Array<{ path: string; name?: string; contentType?: string }>;
  createdAt?: string;
  replyTo?: { authorName?: string; text?: string };
  reactions?: Record<string, string>;
}

type View = "inbox" | "requests" | "archived";
const ms = (iso?: string | null) => (iso ? Date.parse(iso) : Number.NaN);
const isGroup = (c: Doc<Conversation>) => c.kind === "group" || c.id.startsWith("g-");

/** The model's rules (Conversation in the app), for the signed-in [me]. */
function describe(c: Doc<Conversation>, mine: Mine | undefined, me: string) {
  const last = ms(c.lastMessageAt);
  const quietSince = (at?: string) => !!at && (Number.isNaN(last) || last <= ms(at));
  const requestForMe = c.status === "request" && c.requestedOf === me;
  const declinedByMe = c.status === "declined" && c.requestedOf === me;
  const archived = quietSince(mine?.archivedAt);
  const cleared = quietSince(mine?.clearedAt);
  const listed = !Number.isNaN(last) || isGroup(c);
  const shared = ms(c.readAt?.[me]);
  const own = ms(mine?.readAt);
  const read = Math.max(Number.isNaN(shared) ? 0 : shared, Number.isNaN(own) ? 0 : own);
  const unread = !Number.isNaN(last) && !!c.lastSenderId && c.lastSenderId !== me && read < last;
  const others = (c.participants ?? []).filter((u) => u !== me);
  const title = isGroup(c) ? c.name || "Group" : c.names?.[others[0] ?? ""] || "Player";
  return {
    title,
    others,
    requestForMe,
    pendingFromMe: c.status !== "accepted" && !!c.requestedOf && c.requestedOf !== me,
    inInbox: listed && !requestForMe && !declinedByMe && !archived && !cleared,
    inRequests: requestForMe && listed,
    inArchive: archived && !cleared,
    unread: unread && !cleared,
    seen: c.lastSenderId === me && others.length === 1 && !Number.isNaN(last) && ms(c.readAt?.[others[0]!]) >= last,
  };
}

/**
 * Messages, like a desktop mail client: the inbox (or requests, or
 * archived) down the left, the open conversation (?c=) beside it. Read
 * live from Firestore as the app does; every write goes through the API.
 */
export function Messages() {
  const { user } = useAuth();
  const params = useSearchParams();
  const pathname = usePathname();
  const router = useRouter();
  const me = user?.uid ?? "";
  const convs = useLiveQuery<Conversation>(user ? "conversations" : null, [where("participants", "array-contains", me)], me);
  const reads = useLiveQuery<Mine>(user ? `users/${me}/dmReads` : null, [], me);
  const [composing, setComposing] = useState<"direct" | "group" | null>(null);
  const view = (params.get("view") as View) || "inbox";
  const openId = params.get("c");

  const mineById = useMemo(() => new Map((reads.data ?? []).map((r) => [r.id, r] as const)), [reads.data]);
  const all = useMemo(
    () =>
      (convs.data ?? [])
        .map((c) => ({ c, d: describe(c, mineById.get(c.id), me) }))
        .sort((a, b) => (ms(b.c.lastMessageAt) || 0) - (ms(a.c.lastMessageAt) || 0)),
    [convs.data, mineById, me],
  );
  const shown = all.filter(({ d }) => (view === "requests" ? d.inRequests : view === "archived" ? d.inArchive : d.inInbox));
  const requests = all.filter(({ d }) => d.inRequests).length;
  const open = all.find(({ c }) => c.id === openId);

  const go = (q: Record<string, string | null>) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(q)) v === null ? next.delete(k) : next.set(k, v);
    const s = next.toString();
    router.push(s ? `${pathname}?${s}` : pathname, { scroll: false });
  };

  // j / k move through the list; Esc closes the conversation.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      const t = e.target as HTMLElement | null;
      if (e.ctrlKey || e.metaKey || e.altKey || (t && (t.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(t.tagName)))) return;
      if (e.key !== "j" && e.key !== "k" && e.key !== "Escape") return;
      if (e.key === "Escape") return openId && go({ c: null });
      const i = shown.findIndex(({ c }) => c.id === openId);
      const next = shown[e.key === "j" ? Math.min(shown.length - 1, i + 1) : Math.max(0, i - 1)];
      if (next) go({ c: next.c.id });
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  if (!user) return null;
  if (convs.error) return <p className="form-error">{convs.error}</p>;

  return (
    <div className="hub-split chat-split messages">
      <nav className="hub-list" aria-label="Conversations">
        <div className="messages-tools">
          <button type="button" className="btn btn-primary btn-small" onClick={() => setComposing("direct")}>
            New message
          </button>
          <button type="button" className="btn btn-small" onClick={() => setComposing("group")}>
            New group
          </button>
        </div>
        <div className="segmented" role="tablist" aria-label="Show">
          {(["inbox", "requests", "archived"] as const).map((v) => (
            <Link
              key={v}
              role="tab"
              aria-selected={view === v}
              className={view === v ? "on" : ""}
              href={`${pathname}?view=${v}`}
              scroll={false}
            >
              {v === "inbox" ? "Inbox" : v === "requests" ? `Requests${requests ? ` (${requests})` : ""}` : "Archived"}
            </Link>
          ))}
        </div>
        {!convs.data ? (
          <p className="muted" aria-busy="true">
            Loading…
          </p>
        ) : shown.length === 0 ? (
          <p className="empty">
            {view === "requests" ? "No message requests." : view === "archived" ? "Nothing archived." : "No conversations yet."}
          </p>
        ) : (
          <ul className="hub-items conv-list">
            {shown.map(({ c, d }) => (
              <li key={c.id}>
                <Link
                  href={`${pathname}?${new URLSearchParams({ ...(view !== "inbox" && { view }), c: c.id })}`}
                  scroll={false}
                  className={`conv-row${c.id === openId ? " active" : ""}${d.unread ? " unread" : ""}`}
                  aria-current={c.id === openId ? "true" : undefined}
                >
                  <Avatar name={d.title} size={36} />
                  <span className="conv-main">
                    <b>{d.title}</b>
                    <small>
                      {c.lastSenderId === me ? "You: " : ""}
                      {c.lastMessage || (isGroup(c) ? `${c.participants?.length ?? 1} people` : "No messages yet")}
                    </small>
                  </span>
                  <small className="conv-time">
                    <LocalTime iso={c.lastMessageAt ?? undefined} style="relative" />
                  </small>
                  {d.unread && <span className="notice-dot" aria-label="Unread" />}
                </Link>
              </li>
            ))}
          </ul>
        )}
      </nav>
      <section className="hub-detail chat-thread">
        {composing ? (
          <NewConversation
            group={composing === "group"}
            onDone={(id) => {
              setComposing(null);
              if (id) go({ c: id, view: null });
            }}
          />
        ) : open ? (
          <ConversationView key={open.c.id} conv={open.c} info={open.d} mine={mineById.get(open.c.id)} me={me} onClose={() => go({ c: null })} />
        ) : openId && convs.data ? (
          <OpenById id={openId} />
        ) : (
          <div className="card hub-empty">
            <p className="muted">Pick a conversation, or start a new one.</p>
            <p className="muted small">Shortcuts: j and k move through the list, Esc closes.</p>
          </div>
        )}
      </section>
    </div>
  );
}

/** A conversation not in the list yet (just made, or opened from a link). */
function OpenById({ id }: { id: string }) {
  const live = useLiveDoc<Conversation>(`conversations/${id}`);
  if (live.data === undefined && !live.error) return <p className="muted">Loading…</p>;
  return <p className="empty">This conversation isn&apos;t available.</p>;
}

function NewConversation({ group, onDone }: { group: boolean; onDone: (id: string | null) => void }) {
  const { user } = useAuth();
  const [name, setName] = useState("");
  const [people, setPeople] = useState<PickedPerson[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function start(person: PickedPerson) {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      const res = await callApi<OpenConversationResult>(user, "/v1/conversations", { method: "POST", body: { with: person.uid } });
      onDone(res.id);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  async function create(e: FormEvent) {
    e.preventDefault();
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      const res = await callApi<GroupAddedResult>(user, "/v1/conversations/groups", {
        method: "POST",
        body: { name: name.trim(), members: people.map((p) => p.uid) },
      });
      if (res.notAdded.length) window.alert(`Not added (they need to follow you, or don't take messages): ${res.notAdded.join(", ")}`);
      onDone(res.id);
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <div className="card settings-form">
      <h2>{group ? "New group" : "New message"}</h2>
      {group ? (
        <form onSubmit={(e) => void create(e)} className="stack">
          <label>
            Group name
            <input value={name} required maxLength={60} autoFocus onChange={(e) => setName(e.target.value)} />
          </label>
          {people.length > 0 && (
            <ul className="ps-chips">
              {people.map((p) => (
                <li key={p.uid}>
                  {p.name}{" "}
                  <button type="button" className="text-btn" onClick={() => setPeople(people.filter((x) => x.uid !== p.uid))}>
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          )}
          {people.length < groupSizeMax - 1 && (
            <PersonPicker label="Add people (they need to follow you)" exclude={[user?.uid ?? "", ...people.map((p) => p.uid)]} onPick={(p) => setPeople([...people, p])} />
          )}
          <div className="form-actions">
            {error && <span className="form-error">{error}</span>}
            <button type="button" className="btn" onClick={() => onDone(null)}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary" disabled={busy || !name.trim()}>
              Create
            </button>
          </div>
        </form>
      ) : (
        <>
          <PersonPicker label="To" exclude={[user?.uid ?? ""]} disabled={busy} onPick={(p) => void start(p)} />
          {error && <p className="form-error">{error}</p>}
          <p>
            <button type="button" className="btn" onClick={() => onDone(null)}>
              Cancel
            </button>
          </p>
        </>
      )}
    </div>
  );
}

const messageLimit = 60;

function ConversationView({
  conv,
  info,
  mine,
  me,
  onClose,
}: {
  conv: Doc<Conversation>;
  info: ReturnType<typeof describe>;
  mine?: Mine;
  me: string;
  onClose: () => void;
}) {
  const { user } = useAuth();
  const base = `/v1/conversations/${encodeURIComponent(conv.id)}`;
  const messages = useLiveQuery<Message>(`conversations/${conv.id}/messages`, [orderBy("createdAt", "desc"), limit(messageLimit)], conv.id);
  const [replyTo, setReplyTo] = useState<Doc<Message> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [managing, setManaging] = useState(false);
  const body = useRef<HTMLDivElement>(null);
  const hiddenBefore = ms(mine?.clearedAt);
  const list = (messages.data ?? [])
    .filter((m) => Number.isNaN(hiddenBefore) || ms(m.createdAt) > hiddenBefore)
    .slice()
    .reverse();
  const count = list.length;
  useEffect(() => {
    if (body.current) body.current.scrollTop = body.current.scrollHeight;
  }, [count]);

  // Opening it, and each new message while open, marks it read.
  const unread = info.unread || info.requestForMe;
  useEffect(() => {
    if (!user || !unread) return;
    const t = setTimeout(() => void callApi(user, `${base}/read`, { method: "POST" }).catch(() => undefined), 400);
    return () => clearTimeout(t);
  }, [user, base, unread, conv.lastMessageAt]);

  async function act(path: string, method: "POST" | "PUT" | "DELETE" | "PATCH", payload?: unknown, after?: () => void) {
    if (!user) return;
    setError(null);
    try {
      await callApi(user, `${base}${path}`, { method, body: payload });
      after?.();
    } catch (e) {
      setError((e as Error).message);
    }
  }

  const group = isGroup(conv);
  return (
    <div className="card thread">
      <header className="thread-head conv-head">
        <h2>{info.title}</h2>
        <span className="post-admin">
          {group && (
            <button type="button" className="text-btn" onClick={() => setManaging(!managing)} aria-expanded={managing}>
              People
            </button>
          )}
          {info.inArchive ? (
            <button type="button" className="text-btn" onClick={() => void act("/archive", "PUT", { archived: false })}>
              Unarchive
            </button>
          ) : (
            <button type="button" className="text-btn" onClick={() => void act("/archive", "PUT", { archived: true }, onClose)}>
              Archive
            </button>
          )}
          <button
            type="button"
            className="text-btn danger"
            onClick={() => {
              if (window.confirm("Delete this conversation for you? The others keep their copy.")) void act("/clear", "POST", undefined, onClose);
            }}
          >
            Delete
          </button>
        </span>
      </header>
      {managing && group && <GroupPeople conv={conv} me={me} act={act} onLeft={onClose} />}
      {error && <p className="form-error thread-foot">{error}</p>}
      <div className="thread-body" aria-live="polite" ref={body}>
        {messages.error ? (
          <p className="form-error">{messages.error}</p>
        ) : !messages.data ? (
          <p className="muted" aria-busy="true">
            Loading messages…
          </p>
        ) : list.length === 0 ? (
          <p className="empty">No messages yet. Say hello.</p>
        ) : (
          list.map((m, i) => {
            const prev = list[i - 1];
            const grouped = prev && prev.authorId === m.authorId && !m.replyTo;
            const reactions = Object.entries(
              Object.values(m.reactions ?? {}).reduce<Record<string, number>>((acc, e) => ({ ...acc, [e]: (acc[e] ?? 0) + 1 }), {}),
            );
            return (
              <div key={m.id} className={`message${grouped ? " grouped" : ""}${m.authorId === me ? " mine" : ""}`}>
                {!grouped && <Avatar name={m.authorName} size={32} />}
                <div className="message-main">
                  {!grouped && (
                    <p className="message-meta">
                      <b>{m.authorId === me ? "You" : m.authorName || "Player"}</b> <LocalTime iso={m.createdAt} style="relative" />
                    </p>
                  )}
                  {m.replyTo && (
                    <p className="message-reply">
                      ↪ {m.replyTo.authorName}: {m.replyTo.text}
                    </p>
                  )}
                  {m.text && <p className="message-text">{m.text}</p>}
                  {(m.attachments ?? []).map((a) =>
                    a.contentType?.startsWith("image/") ? (
                      <span key={a.path} className="message-image">
                        <MemberImage path={a.path} url="" alt={a.name ?? ""} />
                      </span>
                    ) : (
                      <p key={a.path} className="muted small">
                        📎 {a.name ?? "Attachment"}
                      </p>
                    ),
                  )}
                  {reactions.length > 0 && (
                    <p className="message-reactions">
                      {reactions.map(([e, n]) => (
                        <span key={e} className={m.reactions?.[me] === e ? "mine" : ""}>
                          {e} {n}
                        </span>
                      ))}
                    </p>
                  )}
                </div>
                <MessageActions
                  path={`${base}/messages/${encodeURIComponent(m.id)}`}
                  mine={m.reactions?.[me] ?? null}
                  canDelete={m.authorId === me}
                  onReply={info.requestForMe ? undefined : () => setReplyTo(m)}
                />
              </div>
            );
          })
        )}
        {info.seen && <p className="muted small conv-seen">Seen</p>}
      </div>
      {info.requestForMe ? (
        <footer className="thread-foot conv-request">
          <p>
            <b>{info.title}</b> wants to message you. They won&apos;t know you&apos;ve seen it unless you accept.
          </p>
          <div className="form-actions">
            <button type="button" className="btn" onClick={() => void act("/request", "PUT", { accept: false }, onClose)}>
              Delete
            </button>
            <button type="button" className="btn btn-primary" onClick={() => void act("/request", "PUT", { accept: true })}>
              Accept
            </button>
          </div>
        </footer>
      ) : (
        <>
          {info.pendingFromMe && <p className="muted small thread-foot">Sent as a request: they&apos;ll see it in Message requests.</p>}
          <ChatComposer
            path={`${base}/messages`}
            upload={{ targetId: `conversations/${conv.id}` }}
            placeholder={`Message ${info.title}`}
            replyTo={replyTo ? { id: replyTo.id, authorName: replyTo.authorName, text: replyTo.text } : null}
            onClearReply={() => setReplyTo(null)}
          />
        </>
      )}
    </div>
  );
}

/** A group's people: rename, add someone who follows you, leave, or (its creator) take someone out. */
function GroupPeople({
  conv,
  me,
  act,
  onLeft,
}: {
  conv: Doc<Conversation>;
  me: string;
  act: (path: string, method: "POST" | "PUT" | "DELETE" | "PATCH", payload?: unknown, after?: () => void) => Promise<void>;
  onLeft: () => void;
}) {
  const { user } = useAuth();
  const [name, setName] = useState(conv.name ?? "");
  const [note, setNote] = useState<string | null>(null);
  const people = conv.participants ?? [];
  const creator = conv.createdBy === me;
  return (
    <div className="thread-foot group-people">
      <form
        className="input-row"
        onSubmit={(e) => {
          e.preventDefault();
          void act("", "PATCH", { name: name.trim() });
        }}
      >
        <input aria-label="Group name" value={name} maxLength={60} onChange={(e) => setName(e.target.value)} />
        <button type="submit" className="btn btn-small" disabled={!name.trim() || name.trim() === conv.name}>
          Rename
        </button>
      </form>
      <ul className="people-list">
        {people.map((u) => (
          <li key={u}>
            {u === me ? "You" : conv.names?.[u] || "Player"}
            {u === conv.createdBy && <small className="muted"> · started it</small>}{" "}
            {u === me ? (
              <button type="button" className="text-btn danger" onClick={() => void act(`/members/${encodeURIComponent(me)}`, "DELETE", undefined, onLeft)}>
                Leave
              </button>
            ) : (
              creator && (
                <button type="button" className="text-btn" onClick={() => void act(`/members/${encodeURIComponent(u)}`, "DELETE")}>
                  Remove
                </button>
              )
            )}
          </li>
        ))}
      </ul>
      {people.length < groupSizeMax && (
        <PersonPicker
          label="Add someone who follows you"
          exclude={people}
          onPick={(p) =>
            void (async () => {
              if (!user) return;
              setNote(null);
              try {
                const res = await callApi<GroupAddedResult>(user, `/v1/conversations/${encodeURIComponent(conv.id)}/members`, {
                  method: "POST",
                  body: { members: [p.uid] },
                });
                if (res.notAdded.length) setNote(`${p.name} wasn't added: they need to follow you and take messages.`);
              } catch (e) {
                setNote((e as Error).message);
              }
            })()
          }
        />
      )}
      {note && <p className="muted small">{note}</p>}
    </div>
  );
}
