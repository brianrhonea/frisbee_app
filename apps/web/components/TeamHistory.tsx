"use client";
import { type SeasonTotals, type TeamHistoryEntry, teamHistorySchema } from "@stall10/shared";
import { useCallback, useEffect, useId, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useAuth } from "./AuthProvider";
import { Avatar } from "./ui/Avatar";
import { buttonClass } from "./ui/buttonClass";
import { ListRow } from "./ui/ListRow";
import { StatusPill } from "./ui/StatusPill";
import { EmptyState, ErrorState } from "./ui/States";
import "./team_history.css";

/** The note under the card when a team has more games than the server counts (teamHistoryMaxGames). */
export const partialNote = "Totals may not include every game";

const count = (n: number, one: string) => `${n} ${n === 1 ? one : `${one}s`}`;

/** "3 games · 10 points · 4 goals · 2 assists · 1 block" (the app's historyStatLine). */
export function historyStatLine(t: Pick<SeasonTotals, "games" | "points" | "goals" | "assists" | "blocks">): string {
  return [count(t.games, "game"), count(t.points, "point"), count(t.goals, "goal"), count(t.assists, "assist"), count(t.blocks, "block")].join(" · ");
}

type State = { status: "loading" } | { status: "error"; text: string } | { status: "loaded"; teams: TeamHistoryEntry[] };

/**
 * A player's "Team history" card (the app's TeamHistorySection): every team a team admin linked them to, the
 * ones they left marked "Past", each with their spot and season totals, as `GET /v1/players/:uid/team-history`
 * returns them (the server decides what the viewer may see). On someone else's profile the card appears only
 * when there is something to show. Signed-out visitors never call it.
 */
export function TeamHistory({ uid, isMe }: { uid: string; isMe: boolean }) {
  const { user } = useAuth();
  const viewer = user?.uid;
  const [state, setState] = useState<State>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    if (!user) return;
    let live = true;
    setState({ status: "loading" });
    callApi<unknown>(user, `/v1/players/${encodeURIComponent(uid)}/team-history`).then(
      (raw) => {
        if (!live) return;
        const parsed = teamHistorySchema.safeParse(raw);
        setState(parsed.success ? { status: "loaded", teams: parsed.data.teams } : { status: "error", text: "The server sent something unexpected. Try again." });
      },
      (e) => live && setState({ status: "error", text: problem(e, "Check your connection and try again.") }),
    );
    return () => {
      live = false;
    };
    // The user object changes with token refreshes; the person is what matters.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [viewer, uid, attempt]);
  const retry = useCallback(() => setAttempt((n) => n + 1), []);
  const titleId = useId();

  if (!user) return null;
  // Someone else's: nothing until there is something to show.
  if (!isMe && (state.status !== "loaded" || state.teams.length === 0)) return null;

  let body;
  if (state.status === "loading") {
    body = (
      <div className="th-skeleton" role="status" aria-busy="true">
        <span className="sr-only">Loading team history…</span>
        <span className="th-bone" aria-hidden="true" />
        <span className="th-bone th-bone-short" aria-hidden="true" />
      </div>
    );
  } else if (state.status === "error") {
    body = (
      <ErrorState title="Couldn't load your team history" onRetry={retry} retryLabel="Retry">
        {state.text}
      </ErrorState>
    );
  } else if (state.teams.length === 0) {
    body = <EmptyState quiet>No team history yet. A team admin links you to your spot on a roster.</EmptyState>;
  } else {
    body = (
      <>
        <ul className="th-rows">
          {state.teams.map((t) => (
            <li key={`${t.teamId}/${t.spot.id}`}>
              <HistoryRow entry={t} />
            </li>
          ))}
        </ul>
        {state.teams.some((t) => t.partial) && <p className="muted small th-partial">{partialNote}</p>}
      </>
    );
  }
  return (
    <section className="card team-history" aria-labelledby={titleId}>
      <h2 className="card-title" id={titleId}>
        Team history
      </h2>
      {body}
    </section>
  );
}

function HistoryRow({ entry: t }: { entry: TeamHistoryEntry }) {
  const [expanded, setExpanded] = useState(false);
  const years = Object.keys(t.seasons).sort((a, b) => b.localeCompare(a));
  const shown = expanded ? years : years.slice(0, 1);
  const spot = [t.spot.name, t.spot.number != null ? `#${t.spot.number}` : ""].filter(Boolean).join(" · ");
  const listId = useId();
  return (
    <div className="th-row">
      <ListRow
        leading={<Avatar name={t.teamName} size={40} />}
        title={
          <span className="th-title">
            <span className="th-name">{t.teamName}</span>
            {!t.current && <StatusPill tone="neutral">Past</StatusPill>}
          </span>
        }
        subtitle={spot || undefined}
      />
      <div className="th-seasons">
        {years.length === 0 ? (
          <p className="muted small">No games tracked yet</p>
        ) : (
          <>
            <ul id={listId} className="th-season-list">
              {shown.map((y) => (
                <li key={y} className="small">
                  <b className="th-year">{y}</b> {historyStatLine(t.seasons[y]!)}
                </li>
              ))}
            </ul>
            {years.length > 1 && (
              <button type="button" className={buttonClass({ variant: "ghost", size: "small", className: "th-toggle" })} aria-expanded={expanded} aria-controls={listId} onClick={() => setExpanded((v) => !v)}>
                {expanded ? "Hide other seasons" : `Show all seasons (${years.length})`}
              </button>
            )}
          </>
        )}
      </div>
    </div>
  );
}
