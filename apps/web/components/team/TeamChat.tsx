"use client";
import { limit, orderBy, where } from "firebase/firestore";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { useEffect, useRef } from "react";
import { Avatar } from "../Avatar";
import { LocalTime } from "../LocalTime";
import { MemberImage } from "../MemberImage";
import { useLiveQueries, useLiveQuery } from "@/lib/live";
import { useTeamHub } from "./TeamContext";
import { MembersOnlySection } from "./TeamNav";

interface Room {
  name?: string;
  kind?: "text" | "voice";
  folderId?: string | null;
  position?: number;
}
interface Folder {
  name?: string;
  position?: number;
}
interface Attachment {
  path: string;
  name?: string;
  contentType?: string;
}
interface Message {
  authorId?: string;
  authorName?: string;
  text?: string;
  attachments?: Attachment[];
  createdAt?: string;
  replyTo?: { authorName?: string; text?: string };
  reactions?: Record<string, string>;
}

const messageLimit = 60;
const byPosition = (a: { position?: number; name?: string }, b: { position?: number; name?: string }) =>
  (a.position ?? 0) - (b.position ?? 0) || (a.name ?? "").localeCompare(b.name ?? "");

/**
 * The team's chat: rooms by folder down the left, the open room (?room=)
 * beside them, live. A member sees the rooms their tier, roles or name
 * open to, asked once per audience id as the rules require; chat managers
 * see every room.
 */
export function TeamChat() {
  const { teamId, viewer } = useTeamHub();
  const params = useSearchParams();
  const pathname = usePathname();
  const member = viewer.state === "member" ? viewer : null;
  const all = member?.can("manageChats") ?? false;
  const queries = !member
    ? []
    : all
      ? [[]]
      : [...member.audience.map((id) => [where("readRoles", "array-contains", id)]), [where("readUsers", "array-contains", member.uid)]];
  const rooms = useLiveQueries<Room>(member ? `teams/${teamId}/chats` : null, queries, all ? "all" : (member?.audience.join(",") ?? ""));
  const folders = useLiveQuery<Folder>(member ? `teams/${teamId}/chatFolders` : null, [], "folders");

  if (!member) return <MembersOnlySection what="chat" />;
  if (rooms.error) return <p className="form-error">{rooms.error}</p>;
  if (!rooms.data) return <p className="muted" aria-busy="true">Loading chat…</p>;

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
      <nav className="hub-list chat-rooms" aria-label="Rooms">
        {groups.length === 0 && <p className="empty">No rooms you can read.</p>}
        {groups.map((g) => (
          <div key={g.id || "top"}>
            {g.name && <h3 className="chat-folder">{g.name}</h3>}
            <ul className="hub-items">
              {g.rooms.map((r) => (
                <li key={r.id}>
                  <Link
                    href={`${pathname}?room=${r.id}`}
                    scroll={false}
                    className={`chat-room${r.id === open?.id ? " active" : ""}`}
                    aria-current={r.id === open?.id ? "true" : undefined}
                  >
                    <span aria-hidden="true">{r.kind === "voice" ? "🔊" : "#"}</span> {r.name || "Room"}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </nav>
      <section className="hub-detail chat-thread">
        {open ? (
          open.kind === "voice" ? (
            <div className="card hub-empty">
              <h2>{open.name}</h2>
              <p className="muted">Voice rooms open in the app for now.</p>
            </div>
          ) : (
            <Thread teamId={teamId} roomId={open.id} name={open.name ?? "Room"} me={member.uid} />
          )
        ) : (
          <p className="empty">Pick a room.</p>
        )}
      </section>
    </div>
  );
}

function Thread({ teamId, roomId, name, me }: { teamId: string; roomId: string; name: string; me: string }) {
  const messages = useLiveQuery<Message>(
    `teams/${teamId}/chats/${roomId}/messages`,
    [orderBy("createdAt", "desc"), limit(messageLimit)],
    roomId,
  );
  const body = useRef<HTMLDivElement>(null);
  const count = messages.data?.length ?? 0;
  // Newest at the bottom, in view, without scrolling the page.
  useEffect(() => {
    if (body.current) body.current.scrollTop = body.current.scrollHeight;
  }, [count, roomId]);

  const list = (messages.data ?? []).slice().reverse();
  return (
    <div className="card thread">
      <header className="thread-head">
        <h2># {name}</h2>
      </header>
      <div className="thread-body" aria-live="polite" ref={body}>
        {messages.error ? (
          <p className="form-error">{messages.error}</p>
        ) : !messages.data ? (
          <p className="muted" aria-busy="true">Loading messages…</p>
        ) : list.length === 0 ? (
          <p className="empty">No messages yet.</p>
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
                      <b>{m.authorName || "Member"}</b> <LocalTime iso={m.createdAt} style="relative" />
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
                      <p key={a.path} className="muted small">📎 {a.name ?? "Attachment"}</p>
                    ),
                  )}
                  {reactions.length > 0 && (
                    <p className="message-reactions">
                      {reactions.map(([e, n]) => (
                        <span key={e}>
                          {e} {n}
                        </span>
                      ))}
                    </p>
                  )}
                </div>
              </div>
            );
          })
        )}
      </div>
      <footer className="thread-foot muted small">Sending from the website comes with the Messages slice; reply in the app for now.</footer>
    </div>
  );
}
