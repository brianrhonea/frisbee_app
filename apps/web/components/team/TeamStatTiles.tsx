"use client";
import { goingCount, type InboxRoom, type TeamChatSummary, teamChatSummary } from "@stall10/shared";
import { where } from "firebase/firestore";
import Link from "next/link";
import { useLiveDoc, useLiveQueries } from "@/lib/live";
import { canReadRoom } from "../useTeamChats";
import type { ManagedRoom } from "./ChatManager";
import { useTeamHub } from "./TeamContext";

export type Room = ManagedRoom & InboxRoom;

/**
 * The member's chat in this team, live: the rooms they can read (the chat
 * page's own queries for this team) and which have messages they haven't
 * read (one `chatReads` doc). Undefined until both have loaded, and for
 * anyone who isn't a member. The stat tiles and a community's Chat section
 * (F27) share one.
 */
export function useTeamChatRooms(): TeamChatSummary<Room> | undefined {
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const reads = useLiveDoc<{ rooms?: Record<string, string> }>(member ? `users/${member.uid}/chatReads/${teamId}` : null);
  const all = member?.can("manageChats") ?? false;
  const queries = !member
    ? []
    : all
      ? [[]]
      : [...member.audience.map((id) => [where("readRoles", "array-contains", id)]), [where("readUsers", "array-contains", member.uid)]];
  const rooms = useLiveQueries<Room>(member ? `teams/${teamId}/chats` : null, queries, all ? "all" : (member?.audience.join(",") ?? ""));
  if (!member || !rooms.data || reads.data === undefined) return undefined;
  const readable = rooms.data
    .filter((r) => canReadRoom(member.team, member.uid, r))
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0) || (a.name ?? "").localeCompare(b.name ?? ""));
  return teamChatSummary(readable, reads.data?.rooms ?? {});
}

/**
 * A member's quick numbers at the top of the feed (the app's stat tiles):
 * how many said Going to the next event ([next], which the feed already
 * has), and how many rooms have messages they haven't read (amber while
 * there are any: theirs to read), from [chat] (useTeamChatRooms). No
 * win–loss record: the team's results aren't kept anywhere cheap to read.
 */
export function TeamStatTiles({
  next,
  chat,
}: {
  next?: { id: string; title?: string; rsvps?: Record<string, string> };
  chat: TeamChatSummary<Room> | undefined;
}) {
  const { teamId, viewer } = useTeamHub();
  if (viewer.state !== "member") return null;
  const unread = chat ? chat.unread.length : 0;
  const going = next ? goingCount(next.rsvps) : 0;
  const base = `/teams/${encodeURIComponent(teamId)}`;
  return (
    <div className="stat-tiles">
      {next && (
        <Link className="stat-tile" href={`${base}/schedule?event=${encodeURIComponent(next.id)}`}>
          <span className="stat-tile-top">
            <b>{going}</b> going
          </span>
          <small>{next.title || "Next event"}</small>
        </Link>
      )}
      <Link className={`stat-tile${unread > 0 ? " stat-tile-new" : ""}`} href={`${base}/chat`}>
        <span className="stat-tile-top">
          <b>{unread}</b> new in chat
        </span>
        <small>{unread === 0 ? "All caught up" : unread === 1 ? "1 room" : `${unread} rooms`}</small>
      </Link>
    </div>
  );
}
