"use client";

// A hosted tournament's chats with its organizers (tournament_chats.ts in
// packages/shared; OrganizerChatsCard in the app): the Captains' channel,
// where every entered team's captains and the organizers talk, and each
// team's private thread with the organizers. Opening one brings who is in
// it up to date and goes to it in Messages.
import { type TournamentChatResult, tournamentChatPaths, tournamentChatStatuses } from "@stall10/shared";
import type { User } from "firebase/auth";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { callApi, problem } from "@/lib/client";
import type { TournamentState } from "./useTournament";

type Entry = TournamentState["entries"][number];

/** Whether an entry's captains are in the chats: still invited, applied, accepted or waitlisted. */
export const inChats = (e: Entry | undefined) => !!e && (tournamentChatStatuses as readonly string[]).includes(e.status);

/** Entries the member captains (an admin of the team, or one of its listed captains) that are still in. */
export function myChatEntries(s: TournamentState): Entry[] {
  const uid = s.user?.uid ?? "";
  return s.entries.filter(
    (e) => inChats(e) && (s.myAdminTeams.some((m) => m.id === e.id) || (e.captainIds.includes(uid) && s.myTeams.some((m) => m.id === e.id))),
  );
}

function useOpenChat(user: User | null) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const open = async (path: string) => {
    if (!user) return;
    setBusy(true);
    setError("");
    try {
      const r = await callApi<TournamentChatResult>(user, path, { method: "POST", body: {} });
      router.push(`/messages?c=${encodeURIComponent(r.id)}`);
    } catch (e) {
      setError(problem(e));
      setBusy(false);
    }
  };
  return { busy, error, open };
}

/** "Questions?" on the overview: the Captains' channel, and for captains their team's thread. */
export function OrganizerChats({ s }: { s: TournamentState }) {
  const { busy, error, open } = useOpenChat(s.user ?? null);
  const mine = myChatEntries(s);
  if (!s.user || !s.t || s.t.status === "draft" || (!s.manager && mine.length === 0)) return null;
  const id = encodeURIComponent(s.id);
  return (
    <section className="card">
      <h2 className="card-title">{s.manager ? "Talk with captains" : "Questions?"}</h2>
      <p className="muted small">
        {s.manager
          ? "Answer everyone in the Captains' channel, or message a team from its row on the Teams tab."
          : "Ask the organizers in the Captains' channel, where every team sees the answer, or message them privately about your team."}
      </p>
      <div className="home-actions">
        <button type="button" className="btn btn-small" disabled={busy} onClick={() => void open(tournamentChatPaths.captains(id))}>
          Captains&apos; channel
        </button>
        {!s.manager &&
          mine.map((e) => (
            <button key={e.id} type="button" className="btn btn-small" disabled={busy} onClick={() => void open(tournamentChatPaths.team(id, encodeURIComponent(e.id)))}>
              {mine.length === 1 ? "Message the organizers" : `Message the organizers: ${e.teamName}`}
            </button>
          ))}
      </div>
      {error && <small className="form-error">{error}</small>}
    </section>
  );
}

/** The organizers' "Message" on a team's row. */
export function TeamChatButton({ user, tournamentId, teamId, teamName }: { user: User; tournamentId: string; teamId: string; teamName: string }) {
  const { busy, error, open } = useOpenChat(user);
  return (
    <>
      <button
        type="button"
        className="text-btn"
        disabled={busy}
        title={`Message ${teamName}`}
        onClick={() => void open(tournamentChatPaths.team(encodeURIComponent(tournamentId), encodeURIComponent(teamId)))}
      >
        Message
      </button>
      {error && <small className="form-error">{error}</small>}
    </>
  );
}
