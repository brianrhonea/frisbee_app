"use client";
import { MuteButton } from "../MuteButton";
import { where } from "firebase/firestore";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { type ChatPoll, type InboxRoom, mutedRoomKey, roomUnread } from "@stall10/shared";
import { callApi } from "@/lib/client";
import { useAuth } from "../AuthProvider";
import { canReadRoom } from "../useTeamChats";
import { useMutedRooms } from "../useUnreadChats";
import { Avatar } from "../Avatar";
import { LocalTime } from "../LocalTime";
import { ChatAttachment, type ChatFile } from "../ChatAttachment";
import { loadAtTop, OlderMessages } from "../OlderMessages";
import { ChatComposer, MessageActions } from "../ChatComposer";
import { PendingMessages } from "../PendingMessages";
import { type Doc, useLiveDoc, useLiveQueries, useLiveQuery } from "@/lib/live";
import { usePagedMessages, useThreadScroll } from "@/lib/messages";
import { ChatManager, type ManagedFolder, type ManagedRoom } from "./ChatManager";
import { ChatEventCard, ChatPollCard, CreatePollDialog, PinnedStrip, ShareEventDialog, usePinActions, useRoomPins } from "./ChatExtras";
import { type TeamViewer, useTeamHub } from "./TeamContext";
import { MembersOnlySection } from "./TeamNav";
import { VoiceRoom } from "./meetings/VoiceRoom";
import { useVoice } from "../voice/VoiceProvider";
import { EmptyState, Loading } from "../StatusViews";
import { ReportButton } from "../Report";
import { MentionText, teamMentions } from "../Mentions";

type Room = ManagedRoom & InboxRoom;
type Folder = ManagedFolder;
interface Message {
  authorId?: string;
  authorName?: string;
  text?: string;
  attachments?: ChatFile[];
  createdAt?: string;
  replyTo?: { authorName?: string; text?: string };
  reactions?: Record<string, string>;
  /** A shared team event, shown as a card (F3). */
  event?: { id?: string; title?: string };
  /** A poll, shown as a card (F33). */
  poll?: ChatPoll;
  /** Pinned to the room (F2). */
  pinnedAt?: string;
}

/** Messages per page, live and older (MessageThreadViewModel.pageSize). */
const pageSize = 50;
const byPosition = (a: { position?: number; name?: string }, b: { position?: number; name?: string }) =>
  (a.position ?? 0) - (b.position ?? 0) || (a.name ?? "").localeCompare(b.name ?? "");

/**
 * The team's chat: rooms by folder down the left, the open room (?room=)
 * beside them, live. A member sees the rooms their tier, roles or name
 * open to, asked once per audience id as the rules require; chat managers
 * see every room. Rooms with messages the member hasn't read are bold
 * with a dot; the open one is marked read as messages arrive.
 */
export function TeamChat() {
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const params = useSearchParams();
  const pathname = usePathname();
  const router = useRouter();
  const voice = useVoice();
  const member = viewer.state === "member" ? viewer : null;
  const reads = useLiveDoc<{ rooms?: Record<string, string> }>(member ? `users/${member.uid}/chatReads/${teamId}` : null);
  const all = member?.can("manageChats") ?? false;
  const queries = !member
    ? []
    : all
      ? [[]]
      : [...member.audience.map((id) => [where("readRoles", "array-contains", id)]), [where("readUsers", "array-contains", member.uid)]];
  const rooms = useLiveQueries<Room>(member ? `teams/${teamId}/chats` : null, queries, all ? "all" : (member?.audience.join(",") ?? ""));
  const folders = useLiveQuery<Folder>(member ? `teams/${teamId}/chatFolders` : null, [], "folders");
  const readAt = (id: string) => reads.data?.rooms?.[id];
  // Muting from the list (the room's ⋯, right-click or press and hold), as the app.
  const mutedRooms = useMutedRooms(member?.uid);
  const [menuFor, setMenuFor] = useState<string | null>(null);
  const [muting, setMuting] = useState(false);
  useEffect(() => {
    if (!menuFor) return;
    const close = (e: MouseEvent | KeyboardEvent) => {
      if (e instanceof KeyboardEvent ? e.key === "Escape" : !(e.target as Element).closest?.(".chat-room-item.menu-open")) setMenuFor(null);
    };
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", close);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", close);
    };
  }, [menuFor]);
  async function toggleMute(roomId: string, muted: boolean) {
    if (!user) return;
    setMuting(true);
    try {
      await callApi(user, "/v1/me/notification-settings/mute", { method: "PUT", body: { teamId, roomId, muted: !muted } });
      setMenuFor(null);
    } catch {
      window.alert("Couldn't change that. Try again.");
    } finally {
      setMuting(false);
    }
  }
  const openRoom = (rooms.data ?? []).find((r) => r.id === params.get("room")) ?? (rooms.data ?? []).slice().sort(byPosition).find((r) => r.kind !== "voice");
  const openUnread = !!member && !!openRoom && reads.data !== undefined && canReadRoom(member.team, member.uid, openRoom) && roomUnread(openRoom, readAt(openRoom.id));
  // The open room counts as read, now and as each message arrives.
  useEffect(() => {
    if (!user || !openRoom || !openUnread) return;
    void callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/chats/${encodeURIComponent(openRoom.id)}/read`, { method: "PUT" }).catch(() => undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once per new message in the open room.
  }, [user, teamId, openRoom?.id, openRoom?.lastAt, openUnread]);

  if (!member) return <MembersOnlySection what="chat" />;
  if (rooms.error) return <p className="form-error">{rooms.error}</p>;
  if (!rooms.data) return <Loading label="Loading chat…" />;

  const managing = all && params.get("manage") === "1";
  const sorted = rooms.data.slice().sort(byPosition);
  const openId = params.get("room") ?? sorted.find((r) => r.kind !== "voice")?.id;
  const open = sorted.find((r) => r.id === openId);
  const groups = [
    { id: "", name: "", rooms: sorted.filter((r) => !r.folderId || !folders.data?.some((f) => f.id === r.folderId)) },
    ...(folders.data ?? [])
      .slice()
      .sort(byPosition)
      .map((f) => ({ id: f.id, name: f.name ?? "Folder", rooms: sorted.filter((r) => r.folderId === f.id) })),
  ].filter((g) => g.rooms.length > 0);

  return (
    <div className="hub-split chat-split">
      <nav className="hub-list chat-rooms card" aria-label="Rooms">
        <div className="chat-rooms-head">
          <h2 className="card-title">Rooms</h2>
          {all && (
            <Link className={`chat-manage-link${managing ? " active" : ""}`} href={managing ? pathname : `${pathname}?manage=1`} scroll={false}>
              {managing ? "Back to chat" : "Manage rooms"}
            </Link>
          )}
        </div>
        {groups.length === 0 && <EmptyState>No rooms you can read.</EmptyState>}
        {groups.map((g) => (
          <div key={g.id || "top"} className="chat-folder-group">
            {g.name && <h3 className="chat-folder">{g.name}</h3>}
            <ul className="hub-items">
              {g.rooms.map((r) => {
                const muted = mutedRooms.has(mutedRoomKey(teamId, r.id));
                // Muted: no unread dot, as the app (TeamChatSummary).
                const unread = !muted && r.id !== open?.id && canReadRoom(member.team, member.uid, r) && roomUnread(r, readAt(r.id));
                // As the app: who's in a voice room shows once you're connected to it.
                const inVoice = r.kind === "voice" && voice.isIn(teamId, r.id) && voice.state.connected ? voice.state.people.length : 0;
                return (
                  <li
                    key={r.id}
                    className={`chat-room-item${menuFor === r.id ? " menu-open" : ""}`}
                    // Right-click, or press and hold on a phone: the room's menu (the app's press and hold).
                    onContextMenu={(e) => {
                      if (r.kind === "voice") return;
                      e.preventDefault();
                      setMenuFor(r.id);
                    }}
                  >
                    <Link
                      href={`${pathname}?room=${r.id}`}
                      scroll={false}
                      className={`chat-room${r.id === open?.id ? " active" : ""}${unread ? " unread" : ""}${r.kind === "voice" ? " voice" : ""}`}
                      aria-current={r.id === open?.id ? "true" : undefined}
                    >
                      <span className="chat-room-icon" aria-hidden="true">
                        {r.kind === "voice" ? "🔊" : "#"}
                      </span>
                      <span className="chat-room-name">
                        {r.name || "Room"}
                        {inVoice > 0 && <small className="chat-in-voice">{inVoice} in voice</small>}
                      </span>
                      {muted && (
                        <span className="chat-room-muted" title="Muted" aria-label="Muted">
                          🔕
                        </span>
                      )}
                      {unread && <span className="notice-dot" aria-label="Unread" />}
                    </Link>
                    {r.kind !== "voice" && (
                      <button
                        type="button"
                        className="chat-room-more"
                        aria-label={`Options for ${r.name || "room"}`}
                        aria-expanded={menuFor === r.id}
                        onClick={() => setMenuFor(menuFor === r.id ? null : r.id)}
                      >
                        ⋯
                      </button>
                    )}
                    {menuFor === r.id && (
                      <div className="chat-room-menu" role="menu">
                        <button type="button" role="menuitem" disabled={muting} onClick={() => void toggleMute(r.id, muted)}>
                          {muted ? "Unmute notifications" : "Mute notifications"}
                        </button>
                      </div>
                    )}
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </nav>
      <section className="hub-detail chat-thread">
        {managing ? (
          <ChatManager rooms={sorted} folders={folders.data ?? []} onDone={() => router.replace(pathname, { scroll: false })} />
        ) : open ? (
          open.kind === "voice" ? (
            <VoiceRoom
              key={open.id}
              teamId={teamId}
              roomId={open.id}
              name={open.name ?? "Voice"}
              canSpeak={member.tier === "owner" || member.audience.some((a) => open.writeRoles?.includes(a)) || (open.writeUsers ?? []).includes(member.uid)}
            />
          ) : (
            <Thread
              key={open.id}
              teamId={teamId}
              roomId={open.id}
              name={open.name ?? "Room"}
              me={member.uid}
              canWrite={
                member.tier === "owner" ||
                member.audience.some((a) => open.writeRoles?.includes(a)) ||
                (open.writeUsers ?? []).includes(member.uid)
              }
              canModerate={member.tier === "owner" || member.can("moderate") || member.can("manageChats")}
              canPin={member.tier === "owner" || member.can("manageChats")}
              canShareEvents={member.can("manageEvents")}
              viewer={member}
            />
          )
        ) : (
          <EmptyState>Pick a room.</EmptyState>
        )}
      </section>
    </div>
  );
}

function Thread({
  teamId,
  roomId,
  name,
  me,
  canWrite,
  canModerate,
  canPin,
  canShareEvents,
  viewer,
}: {
  teamId: string;
  roomId: string;
  name: string;
  me: string;
  canWrite: boolean;
  canModerate: boolean;
  /** The owner and chat managers pin messages (F2) and close anyone's poll (F33). */
  canPin: boolean;
  /** Members who add the team's events share them here as cards (F3). */
  canShareEvents: boolean;
  viewer: TeamViewer;
}) {
  const [replyTo, setReplyTo] = useState<Doc<Message> | null>(null);
  // The message whose reaction bubble is open (double-click, as the app's double-tap).
  const [reacting, setReacting] = useState<string | null>(null);
  const [sharing, setSharing] = useState(false);
  const [polling, setPolling] = useState(false);
  const names = viewer.state === "member" ? (viewer.team.memberNames ?? {}) : {};
  const nameOf = (uid: string) => names[uid] || "Member";
  // @mentions: suggested in the composer and marked in messages, as the app.
  const mentions =
    viewer.state === "member" ? teamMentions(viewer.team, me, viewer.tier === "owner" || viewer.can("manageChats")) : undefined;
  const pins = useRoomPins<Message>(teamId, roomId);
  const pinActions = usePinActions(teamId, roomId);
  // From the live pins only: older pages of messages aren't live.
  const pinned = new Set((pins.data ?? []).map((p) => p.id));
  const base = `/v1/teams/${encodeURIComponent(teamId)}/chats/${encodeURIComponent(roomId)}/messages`;
  const messages = usePagedMessages<Message>(`teams/${teamId}/chats/${roomId}/messages`, pageSize);
  const body = useRef<HTMLDivElement>(null);
  const list = messages.list ?? [];
  // Newest at the bottom, in view, without scrolling the page; older pages keep the reader's place.
  useThreadScroll(body, list[0]?.id, list[list.length - 1]?.id);
  return (
    <div className="card thread">
      <header className="thread-head">
        <h2># {name}</h2>
        <span className="post-admin">
          <MuteButton target={{ teamId, roomId }} />
        </span>
      </header>
      <PinnedStrip pins={pins.data ?? []} canPin={canPin} actions={pinActions} />
      <div className="thread-body" aria-live="polite" ref={body} onScroll={loadAtTop(messages)}>
        <OlderMessages paged={messages} />
        {messages.error ? (
          <p className="form-error">{messages.error}</p>
        ) : !messages.list ? (
          <Loading label="Loading messages…" />
        ) : list.length === 0 ? (
          <EmptyState>No messages yet.</EmptyState>
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
                      <b>{m.authorName || "Member"}</b> <LocalTime iso={m.createdAt} style="relative" />
                      {pinned.has(m.id) && <span className="message-pinned">📌 Pinned</span>}
                    </p>
                  )}
                  {m.replyTo && (
                    <p className="message-reply">
                      ↪ {m.replyTo.authorName}: {m.replyTo.text}
                    </p>
                  )}
                  {m.text && (
                    <p className="message-text">
                      <MentionText text={m.text} mentions={mentions} />
                    </p>
                  )}
                  {m.event?.id && <ChatEventCard teamId={teamId} eventId={m.event.id} uid={me} />}
                  {m.poll && (
                    <ChatPollCard
                      teamId={teamId}
                      roomId={roomId}
                      messageId={m.id}
                      authorId={m.authorId}
                      initial={m.poll}
                      uid={me}
                      canManage={canPin}
                      nameOf={nameOf}
                    />
                  )}
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
                  path={`${base}/${encodeURIComponent(m.id)}`}
                  mine={m.reactions?.[me] ?? null}
                  canDelete={m.authorId === me || canModerate}
                  onReply={canWrite ? () => setReplyTo(m) : undefined}
                  onDeleted={() => messages.removed(m.id)}
                  picking={reacting === m.id}
                  onPickingChange={(open) => setReacting(open ? m.id : null)}
                  extra={
                    m.createdAt && (canPin || m.authorId !== me) ? (
                      <>
                        {canPin && (
                          <button type="button" className="text-btn" onClick={() => void (pinned.has(m.id) ? pinActions.unpin(m.id) : pinActions.pin(m.id))}>
                            {pinned.has(m.id) ? "Unpin" : "Pin"}
                          </button>
                        )}
                        {m.authorId !== me && (
                          <ReportButton
                            target={{ kind: "teamMessage", teamId, roomId, messageId: m.id }}
                            authorName={m.authorName || "this player"}
                          />
                        )}
                      </>
                    ) : undefined
                  }
                />
              </div>
            );
          })
        )}
        <PendingMessages kind="teamChat" target={`${teamId}/${roomId}`} shown={list} />
      </div>
      {canWrite ? (
        <ChatComposer
          path={base}
          upload={{ targetId: `teams/${teamId}/chats/${roomId}` }}
          placeholder={`Message #${name}`}
          replyTo={replyTo ? { id: replyTo.id, authorName: replyTo.authorName, text: replyTo.text } : null}
          onClearReply={() => setReplyTo(null)}
          draftKey={`chat_${teamId}_${roomId}`}
          outbox={{ kind: "teamChat", target: `${teamId}/${roomId}` }}
          onShareEvent={canShareEvents ? () => setSharing(true) : undefined}
          onCreatePoll={() => setPolling(true)}
          mentions={mentions}
        />
      ) : (
        <footer className="thread-foot muted small">You can read this room but not post in it.</footer>
      )}
      {sharing && <ShareEventDialog teamId={teamId} roomId={roomId} viewer={viewer} onClose={() => setSharing(false)} />}
      {polling && <CreatePollDialog teamId={teamId} roomId={roomId} onClose={() => setPolling(false)} />}
    </div>
  );
}
