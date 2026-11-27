"use client";
import { MuteButton } from "./MuteButton";
import { directConversationId, groupSizeMax, mutedConversationKey, type GroupAddedResult, typingFreshMs } from "@stall10/shared";
import { where } from "firebase/firestore";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { type FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { callApi } from "@/lib/client";
import { PendingMessages } from "./PendingMessages";
import { type Doc, useLiveDoc, useLivePaged, useLiveQuery } from "@/lib/live";
import { usePagedMessages, useThreadScroll } from "@/lib/messages";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./Avatar";
import { ChatAttachment, type ChatFile } from "./ChatAttachment";
import { ChatComposer, MessageActions } from "./ChatComposer";
import { useBlocks, unblockPerson } from "@/lib/moderation";
import { BlockButton, ReportButton } from "./Report";
import { LocalTime } from "./LocalTime";
import { openConversation } from "./MessageButton";
import { LoadMore } from "./LoadMore";
import { loadAtTop, OlderMessages } from "./OlderMessages";
import { type PickedPerson, PersonPicker } from "./PersonPicker";
import { isTyping, validId } from "@/lib/text";
import { useTeamChats } from "./useTeamChats";
import { useMutedRooms } from "./useUnreadChats";
import { type Conversation, describe, isGroup, type Mine, ms } from "./conversations";
import "./member.css";
import { Button } from "./ui/Button";
import { useConfirm } from "@/components/ui/ConfirmDialog";
import { ErrorNote } from "@/components/StatusViews";

interface Message {
  authorId?: string;
  authorName?: string;
  text?: string;
  attachments?: ChatFile[];
  createdAt?: string;
  replyTo?: { authorName?: string; text?: string };
  reactions?: Record<string, string>;
}

const views = ["inbox", "requests", "archived"] as const;
type View = (typeof views)[number];
/** Conversations per page (no index orders them by last message, so "More conversations" reads the next page). */
const conversationPage = 200;
/**
 * Messages, like a desktop mail client: the inbox (or requests, or
 * archived) down the left, the open conversation (?c=) beside it. The
 * inbox lists the member's team and community chats first; each opens
 * on its team's Chat page. Read
 * live from Firestore as the app does; every write goes through the API.
 */
export function Messages() {
  const { user } = useAuth();
  const params = useSearchParams();
  const pathname = usePathname();
  const router = useRouter();
  const me = user?.uid ?? "";
  // A page at a time, and each conversation's read state with it.
  const convs = useLivePaged<Conversation>(user ? "conversations" : null, [where("participants", "array-contains", me)], me, conversationPage);
  const reads = useLivePaged<Mine>(user ? `users/${me}/dmReads` : null, [], me, conversationPage * 2);
  const loadMore = () => {
    convs.loadMore();
    reads.loadMore();
  };
  const [composing, setComposing] = useState<"direct" | "group" | null>(null);
  // Search by name, as the app's inbox does (InboxViewModel.setQuery).
  const [search, setSearch] = useState("");
  const rawView = params.get("view");
  const view: View = views.find((v) => v === rawView) ?? "inbox";
  const openId = validId(params.get("c"));
  const to = params.get("to");

  const mineById = useMemo(() => new Map((reads.data ?? []).map((r) => [r.id, r] as const)), [reads.data]);
  const all = useMemo(
    () =>
      (convs.data ?? [])
        .map((c) => ({ c, d: describe(c, mineById.get(c.id), me) }))
        .sort((a, b) => (ms(b.c.lastMessageAt) || 0) - (ms(a.c.lastMessageAt) || 0)),
    [convs.data, mineById, me],
  );
  const blocks = useBlocks(user);
  const q = search.trim().toLowerCase();
  // Requests from someone blocked either way aren't shown at all.
  const shown = all.filter(
    ({ c, d }) =>
      (view === "requests" ? d.inRequests && !(!isGroup(c) && blocks.hides(d.others[0])) : view === "archived" ? d.inArchive : d.inInbox) &&
      (!q || d.title.toLowerCase().includes(q)),
  );
  const requests = all.filter(({ c, d }) => d.inRequests && !(!isGroup(c) && blocks.hides(d.others[0]))).length;
  const open = all.find(({ c }) => c.id === openId);
  const teamChats = useTeamChats(user?.uid);
  // Muted conversations have no unread bubble, as on the Chats tab.
  const muted = useMutedRooms(user?.uid);
  const shownTeams =
    view === "inbox" ? (teamChats.chats ?? []).filter((c) => !q || (c.team.name ?? "").toLowerCase().includes(q)) : [];
  const headed = shownTeams.length > 0 && shown.length > 0;
  // Each section folds away for this browser session, as the app (until it restarts).
  const [folded, setFolded] = useFoldedSections();
  const teamsFolded = headed && folded.has("teams");
  const directFolded = headed && folded.has("direct");
  const heading = (key: Section, text: string, count: number) => {
    const isFolded = folded.has(key);
    return (
      <h3 className="conv-heading">
        <button type="button" className="conv-heading-btn" aria-expanded={!isFolded} onClick={() => setFolded(key)}>
          <span>{text}</span>
          {isFolded && <small>{count}</small>}
          <span className="conv-heading-chevron" aria-hidden="true">
            {isFolded ? "▸" : "▾"}
          </span>
        </button>
      </h3>
    );
  };

  const go = (q: Record<string, string | null>) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(q)) v === null ? next.delete(k) : next.set(k, v);
    const s = next.toString();
    router.push(s ? `${pathname}?${s}` : pathname, { scroll: false });
  };

  // /messages?to=<uid> (a shared link): a conversation with them that
  // already exists just opens. A new one is only started when the member
  // clicks "Message <name>" (StartConversation), as the app starts one only
  // from the profile's Message button: following a link never starts a
  // conversation for anyone.
  const toUid = to && to !== me && /^[A-Za-z0-9_-]{1,128}$/.test(to) ? to : null;
  const toId = toUid ? directConversationId(me, toUid) : null;
  // It may be past the pages loaded: ask for it by id too (the rules refuse a missing one).
  const toListed = !!toId && all.some(({ c }) => c.id === toId);
  const toDoc = useLiveDoc<Conversation>(toId && convs.data && !toListed ? `conversations/${toId}` : null);
  const toExists = toListed || !!toDoc.data;
  const toKnown = !toId || toExists || toDoc.data === null || !!toDoc.error;
  const showConversation = (id: string) => {
    const next = new URLSearchParams(params);
    next.delete("to");
    next.delete("view");
    next.set("c", id);
    router.replace(`${pathname}?${next}`, { scroll: false });
  };
  useEffect(() => {
    if (toId && toExists) showConversation(toId);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once it's known to exist.
  }, [toId, toExists]);

  // j / k move through the list; Esc closes the conversation. One
  // listener, reading the latest list through a ref.
  const keys = useRef({ shown, openId, go });
  keys.current = { shown, openId, go };
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.ctrlKey || e.metaKey || e.altKey || isTyping(e.target)) return;
      if (e.key !== "j" && e.key !== "k" && e.key !== "Escape") return;
      const { shown, openId, go } = keys.current;
      if (e.key === "Escape") return openId && go({ c: null });
      const i = shown.findIndex(({ c }) => c.id === openId);
      const next = shown[e.key === "j" ? Math.min(shown.length - 1, i + 1) : Math.max(0, i - 1)];
      if (next) go({ c: next.c.id });
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  if (!user) return null;
  if (convs.error) return <ErrorNote>{convs.error}</ErrorNote>;

  return (
    <div className="hub-split chat-split messages">
      <nav className="hub-list" aria-label="Conversations">
        <div className="messages-tools">
          <Button variant="primary" size="small" onClick={() => setComposing("direct")}>
            New message
          </Button>
          <Button size="small" onClick={() => setComposing("group")}>
            New group
          </Button>
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
              {v === "inbox" ? "Chats" : v === "requests" ? `Requests${requests ? ` (${requests})` : ""}` : "Archived"}
            </Link>
          ))}
        </div>
        <input
          className="search-input"
          type="search"
          placeholder="Search messages"
          aria-label="Search conversations by name"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        {shownTeams.length > 0 && (
          <>
            {headed && heading("teams", "Team chats", shownTeams.length)}
            <ul className="hub-items conv-list" aria-label="Team chats" hidden={teamsFolded}>
              {shownTeams.map((c) => (
                <li key={c.team.id}>
                  <Link
                    href={`/teams/${encodeURIComponent(c.team.id)}/chat${c.open ? `?room=${encodeURIComponent(c.open.id)}` : ""}`}
                    className={`conv-row${c.unread.length > 0 ? " unread" : ""}`}
                  >
                    <Avatar name={c.team.name ?? "Team"} size={36} />
                    <span className="conv-main">
                      <b>{c.team.name ?? "Team"}</b>
                      <small className={c.mention ? "conv-mention" : undefined}>{c.subtitle}</small>
                    </span>
                    <small className="conv-time">
                      <LocalTime iso={c.lastAt ?? undefined} style="relative" />
                    </small>
                    {c.unread.length > 0 && <span className="notice-dot" aria-label="Unread" />}
                  </Link>
                </li>
              ))}
            </ul>
            {headed && heading("direct", "Direct messages", shown.length)}
          </>
        )}
        {!convs.data ? (
          <p className="muted" aria-busy="true">
            Loading…
          </p>
        ) : shown.length === 0 && shownTeams.length > 0 && !q ? null : shown.length === 0 ? (
          <p className="empty">
            {q
              ? "No conversations match your search."
              : view === "requests"
                ? "No message requests."
                : view === "archived"
                  ? "Nothing archived."
                  : "No conversations yet."}
          </p>
        ) : (
          <ul className="hub-items conv-list" hidden={directFolded}>
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
                  {d.unread && !muted.has(mutedConversationKey(c.id)) && <span className="notice-dot" aria-label="Unread" />}
                </Link>
              </li>
            ))}
          </ul>
        )}
        {convs.data && !directFolded && <LoadMore paged={{ ...convs, loadMore }} label="More conversations" />}
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
          <OpenById key={openId} id={openId} me={me} onClose={() => go({ c: null })} />
        ) : toUid && convs.data && toKnown && !toExists ? (
          <StartConversation key={toUid} uid={toUid} onStarted={showConversation} onCancel={() => go({ to: null })} />
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

/**
 * ?to=<uid> with no conversation yet: who it would be with, and "Message
 * <name>". Only that click starts it (`POST /v1/conversations`); their
 * message settings decide whether it's a conversation or a request.
 */
function StartConversation({ uid, onStarted, onCancel }: { uid: string; onStarted: (id: string) => void; onCancel: () => void }) {
  const { user } = useAuth();
  const profile = useLiveDoc<{ name?: string; photoUrl?: string }>(`profiles/${uid}`);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (profile.data === undefined && !profile.error) return <p className="muted">Loading…</p>;
  if (profile.data === null) return <p className="empty">That player doesn&apos;t exist.</p>;
  const name = profile.data?.name || "this player";

  async function start() {
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      onStarted((await openConversation(user, uid)).id);
    } catch (e) {
      setError((e as Error).message);
      setBusy(false);
    }
  }

  return (
    <div className="card settings-form">
      <h2>New message</h2>
      <p>
        <Avatar name={name} url={profile.data?.photoUrl || undefined} size={36} /> <b>{name}</b>
      </p>
      {error && (
        <ErrorNote>
          {error}
        </ErrorNote>
      )}
      <div className="form-actions">
        <button type="button" className="btn" onClick={onCancel}>
          Cancel
        </button>
        <button type="button" className="btn btn-primary" disabled={busy} onClick={() => void start()}>
          Message {name}
        </button>
      </div>
    </div>
  );
}

/** A conversation not in the pages loaded (just made, older, or opened from a link), read by its id. */
function OpenById({ id, me, onClose }: { id: string; me: string; onClose: () => void }) {
  const live = useLiveDoc<Conversation>(`conversations/${id}`);
  const mine = useLiveDoc<Mine>(`users/${me}/dmReads/${id}`);
  if (live.data === undefined && !live.error) return <p className="muted">Loading…</p>;
  if (!live.data) return <p className="empty">This conversation isn&apos;t available.</p>;
  const m = mine.data ?? undefined;
  return <ConversationView conv={live.data} info={describe(live.data, m, me)} mine={m} me={me} onClose={onClose} />;
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
      const res = await openConversation(user, person.uid);
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
          {error && <ErrorNote>{error}</ErrorNote>}
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

/** Messages per page, live and older (MessageThreadViewModel.pageSize). */
const pageSize = 50;

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
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const base = `/v1/conversations/${encodeURIComponent(conv.id)}`;
  const hiddenBefore = ms(mine?.clearedAt);
  const messages = usePagedMessages<Message>(`conversations/${conv.id}/messages`, pageSize, hiddenBefore);
  const [replyTo, setReplyTo] = useState<Doc<Message> | null>(null);
  // The message whose reaction bubble is open (double-click, as the app's double-tap).
  const [reacting, setReacting] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [managing, setManaging] = useState(false);
  const typing = useTyping(conv.id, me, conv.names);
  const body = useRef<HTMLDivElement>(null);
  const blocks = useBlocks(user);
  const group = isGroup(conv);
  // A direct conversation with someone blocked either way can't go on; in a
  // group, their messages aren't shown.
  const other = group ? null : (info.others[0] ?? null);
  const blockedHere = !!other && blocks.hides(other);
  const list = (messages.list ?? []).filter(
    (m) => (Number.isNaN(hiddenBefore) || ms(m.createdAt) > hiddenBefore) && !(group && blocks.hides(m.authorId)),
  );
  useThreadScroll(body, list[0]?.id, list[list.length - 1]?.id);

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

  return (
    <div className="card thread">
      <header className="thread-head conv-head">
        <h2>{info.title}</h2>
        <span className="post-admin">
          <MuteButton target={{ conversationId: conv.id }} />
          {other && !blockedHere && (
            <>
              <ReportButton target={{ kind: "user", uid: other }} authorName={info.title} label="Report" />
              <BlockButton uid={other} name={info.title} label="Block" />
            </>
          )}
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
            onClick={async () => {
              if ((await askConfirm({ message: "Delete this conversation for you? The others keep their copy.", confirmLabel: "Delete", destructive: true }))) void act("/clear", "POST", undefined, onClose);
            }}
          >
            Delete
          </button>
        </span>
      </header>
      {managing && group && <GroupPeople conv={conv} me={me} act={act} onLeft={onClose} />}
      {error && <p className="form-error thread-foot">{error}</p>}
      <div className="thread-body" aria-live="polite" ref={body} onScroll={loadAtTop(messages)}>
        <OlderMessages paged={messages} />
        {messages.error ? (
          <ErrorNote>{messages.error}</ErrorNote>
        ) : !messages.list ? (
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
              <div key={m.id} className={`message${grouped ? " grouped" : ""}${m.authorId === me ? " mine" : ""}`} onDoubleClick={m.createdAt ? () => setReacting(m.id) : undefined}>
                {grouped && (
                  <span className="message-time">
                    <LocalTime iso={m.createdAt} style="time" />
                  </span>
                )}
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
                  {(m.attachments ?? []).map((a) => (
                    <ChatAttachment key={a.path} file={a} />
                  ))}
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
                  onDeleted={() => messages.removed(m.id)}
                  picking={reacting === m.id}
                  onPickingChange={(open) => setReacting(open ? m.id : null)}
                  extra={
                    m.authorId !== me && m.createdAt ? (
                      <ReportButton
                        target={{ kind: "directMessage", conversationId: conv.id, messageId: m.id }}
                        authorName={m.authorName || "this player"}
                      />
                    ) : undefined
                  }
                />
              </div>
            );
          })
        )}
        <PendingMessages kind="directMessage" target={conv.id} shown={list} />
        {info.seen && <p className="muted small conv-seen">Seen</p>}
        {typing.others.length > 0 && (
          <p className="muted small conv-typing" aria-live="polite">
            {typing.others.length === 1 ? `${typing.others[0]} is typing…` : "Several people are typing…"}
          </p>
        )}
      </div>
      {blockedHere && other ? (
        <footer className="thread-foot conv-request">
          {blocks.blockedByMe(other) ? (
            <>
              <p>You blocked {info.title}. Neither of you can message the other.</p>
              <div className="form-actions">
                <button
                  type="button"
                  className="btn"
                  onClick={async () => {
                    if (user && (await askConfirm({ title: `Unblock ${info.title}?`, message: "You'll see each other's posts and can message again.", confirmLabel: "Unblock" }))) {
                      void unblockPerson(user, other).catch((e) => setError((e as Error).message));
                    }
                  }}
                >
                  Unblock
                </button>
              </div>
            </>
          ) : (
            <p>You can&apos;t message {info.title}.</p>
          )}
        </footer>
      ) : info.requestForMe ? (
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
            onTyping={typing.report}
            draftKey={`dm_${conv.id}`}
            outbox={{ kind: "directMessage", target: conv.id }}
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
  // A tournament's chat follows its entries: only who's in it shows here.
  if (conv.kind === "tournament") {
    return (
      <div className="thread-foot group-people">
        <p className="muted small">
          The organizers and the captains of teams in the tournament.{" "}
          {conv.tournamentId && <Link href={`/tournaments/${encodeURIComponent(conv.tournamentId)}`}>Open the tournament</Link>}
        </p>
        <ul className="people-list">
          {people.map((u) => (
            <li key={u}>{u === me ? "You" : conv.names?.[u] || "Player"}</li>
          ))}
        </ul>
      </div>
    );
  }
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

/**
 * Who else is typing in [convId] (conversations/{id}/typing, fresh marks
 * only), and [report] to mark the member's own, sent at most every few
 * seconds and cleared when they stop.
 */
function useTyping(convId: string, me: string, names: Record<string, string> | undefined) {
  const { user } = useAuth();
  const marks = useLiveQuery<{ at?: string }>(`conversations/${convId}/typing`, [], convId);
  const sentAt = useRef(0);
  const on = useRef(false);
  const [, tick] = useState(0);
  // Marks go stale on their own; look again every few seconds.
  useEffect(() => {
    const t = setInterval(() => tick((n) => n + 1), 3000);
    return () => clearInterval(t);
  }, []);
  const send = (typing: boolean) => {
    if (!user) return;
    void callApi(user, `/v1/conversations/${encodeURIComponent(convId)}/typing`, { method: "PUT", body: { typing } }).catch(() => undefined);
  };
  // Clear the mark on leaving the conversation.
  useEffect(
    () => () => {
      if (on.current) send(false);
      on.current = false;
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [convId],
  );
  const report = (typing: boolean) => {
    const now = Date.now();
    if (typing && (!on.current || now - sentAt.current > typingFreshMs / 2)) {
      on.current = true;
      sentAt.current = now;
      send(true);
    } else if (!typing && on.current) {
      on.current = false;
      send(false);
    }
  };
  const fresh = Date.now() - typingFreshMs;
  const others = (marks.data ?? [])
    .filter((d) => d.id !== me && d.at && new Date(d.at).getTime() > fresh)
    .map((d) => names?.[d.id] || "Someone");
  return { others, report };
}

type Section = "teams" | "direct";
const foldedKey = "stall10.chats.folded";

/** Chats sections folded away, kept in sessionStorage (this tab, until it closes). */
function useFoldedSections(): [Set<Section>, (s: Section) => void] {
  const [folded, setFolded] = useState<Set<Section>>(new Set());
  useEffect(() => {
    try {
      const saved = JSON.parse(sessionStorage.getItem(foldedKey) ?? "[]") as Section[];
      if (Array.isArray(saved) && saved.length > 0) setFolded(new Set(saved));
    } catch {
      // No storage (private window): stays unfolded.
    }
  }, []);
  const toggle = (s: Section) =>
    setFolded((prev) => {
      const next = new Set(prev);
      if (!next.delete(s)) next.add(s);
      try {
        sessionStorage.setItem(foldedKey, JSON.stringify([...next]));
      } catch {
        // Not saved; still folds for this page.
      }
      return next;
    });
  return [folded, toggle];
}
