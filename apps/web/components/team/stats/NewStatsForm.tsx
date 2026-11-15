"use client";
import {
  type CreatedId,
  gameToTargets,
  lineSources,
  linesForEvent,
  type SaveStatsGameRequest,
  type SaveStatsTournamentRequest,
  type SaveTeamEventResult,
  type StatsGame,
  type StatsPlayer,
  type StatsTournament,
  timeoutChoices,
} from "@stall10/shared";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useAuth } from "../../AuthProvider";
import { apiUrl, gameUrl, type LinkableEvent, shortDate, tournamentUrl } from "./data";
import "./stats.css";

const typeLabel: Record<string, string> = {
  practice: "Practice",
  game: "Game",
  tournament: "Tournament",
  scrimmage: "Scrimmage",
  other: "Other",
  pickup: "Pickup",
};

/** yyyy-mm-dd in local time, for a date input. */
const dayOf = (iso: string) => {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
/** A picked day, at midnight local time, as the app's date picker gives it. */
const atDay = (day: string) => {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(y, m - 1, d).toISOString();
};

/**
 * New game or tournament (the app's _NewDialog): optionally linked to a
 * schedule event, whose saved lines come along; a quick new event for
 * those who may add them. Opens the new game or tournament.
 */
export function NewStatsForm({
  teamId,
  kind,
  events,
  tournaments,
  games,
  players,
  canCreateEvents,
  onClose,
}: {
  teamId: string;
  kind: "game" | "tournament";
  events: LinkableEvent[];
  tournaments: StatsTournament[];
  games: StatsGame[];
  players: StatsPlayer[];
  canCreateEvents: boolean;
  onClose: () => void;
}) {
  const { user } = useAuth();
  const router = useRouter();
  const tournament = kind === "tournament";
  const [name, setName] = useState("");
  const [date, setDate] = useState(() => new Date().toISOString());
  const [gameTo, setGameTo] = useState(15);
  const [timeouts, setTimeouts] = useState(2);
  const [extra, setExtra] = useState<LinkableEvent[]>([]);
  const [eventId, setEventId] = useState("");
  const [creatingEvent, setCreatingEvent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const all = [...extra, ...events.filter((e) => !extra.some((x) => x.id === e.id))];
  const event = all.find((e) => e.id === eventId) ?? null;
  const lines = linesForEvent(event?.id, lineSources(tournaments, games));

  const link = (id: string) => {
    setEventId(id);
    const e = all.find((x) => x.id === id);
    if (e) {
      setDate(e.startsAt);
      if (!name.trim() && tournament) setName(e.title);
    }
  };

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!user || !name.trim() || busy) return;
    setBusy(true);
    setError("");
    try {
      if (tournament) {
        const body: SaveStatsTournamentRequest = {
          name: name.trim(),
          startDate: date,
          location: event?.location ?? "",
          eventId: event?.id ?? null,
          roster: players.map((p) => p.id),
          lines,
        };
        const { id } = await callApi<CreatedId>(user, apiUrl(teamId, "/stats-tournaments"), { method: "POST", body });
        router.push(tournamentUrl(teamId, id));
      } else {
        const body: SaveStatsGameRequest = {
          opponent: name.trim(),
          date,
          gameTo,
          timeoutsPerHalf: timeouts,
          tournamentId: null,
          eventId: event?.id ?? null,
          lines,
        };
        const { id } = await callApi<CreatedId>(user, apiUrl(teamId, "/stats-games"), { method: "POST", body });
        router.push(gameUrl(teamId, id));
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Couldn't create it. Try again.");
      setBusy(false);
    }
  }

  return (
    <form className="card settings-form st-new" onSubmit={submit}>
      <h3 className="card-title">{tournament ? "New tournament" : "New game"}</h3>
      <label className="field">
        <span>Link to schedule event</span>
        <select value={eventId} onChange={(e) => link(e.target.value)}>
          <option value="">None</option>
          {all.map((e) => (
            <option key={e.id} value={e.id}>
              {e.title} · {typeLabel[e.type] ?? e.type} · {shortDate(e.startsAt)}
            </option>
          ))}
        </select>
      </label>
      {canCreateEvents && !creatingEvent && (
        <button type="button" className="text-btn" onClick={() => setCreatingEvent(true)}>
          {all.length === 0 ? "No events yet. Create one" : "Create a new event"}
        </button>
      )}
      {creatingEvent && (
        <NewEvent
          teamId={teamId}
          tournament={tournament}
          title={tournament ? name.trim() : ""}
          day={dayOf(date)}
          onDone={(created) => {
            setCreatingEvent(false);
            if (created) {
              setExtra((x) => [created, ...x]);
              setEventId(created.id);
              setDate(created.startsAt);
              if (!name.trim() && tournament) setName(created.title);
            }
          }}
        />
      )}
      {lines.length > 0 && (
        <p className="form-notice small">
          {lines.length} saved line{lines.length === 1 ? "" : "s"} from this event will be imported.
        </p>
      )}
      <label className="field">
        <span>{tournament ? "Tournament name" : "Opponent"}</span>
        <input autoFocus value={name} maxLength={100} onChange={(e) => setName(e.target.value)} />
      </label>
      <label className="field">
        <span>Date</span>
        <input type="date" value={dayOf(date)} onChange={(e) => e.target.value && setDate(atDay(e.target.value))} />
      </label>
      {!tournament && <GameSettings gameTo={gameTo} timeouts={timeouts} onGameTo={setGameTo} onTimeouts={setTimeouts} />}
      {error && <p className="form-error">{error}</p>}
      <div className="form-actions">
        <button type="button" className="btn btn-small" onClick={onClose}>
          Cancel
        </button>
        <button type="submit" className="btn btn-small btn-primary" disabled={!name.trim() || busy}>
          {busy ? "Creating…" : "Create"}
        </button>
      </div>
    </form>
  );
}

/** Game to and timeouts per half (GameToField, TimeoutsField). */
export function GameSettings({
  gameTo,
  timeouts,
  onGameTo,
  onTimeouts,
  minimum = 1,
}: {
  gameTo: number;
  timeouts: number;
  onGameTo: (n: number) => void;
  onTimeouts: (n: number) => void;
  minimum?: number;
}) {
  return (
    <>
      <div className="field">
        <span>Game to</span>
        <div className="segmented" role="radiogroup" aria-label="Game to">
          {gameToTargets
            .filter((t) => t >= minimum || t === gameTo)
            .map((t) => (
              <button key={t} type="button" role="radio" aria-checked={t === gameTo} className={t === gameTo ? "on" : ""} onClick={() => onGameTo(t)}>
                {t}
              </button>
            ))}
        </div>
      </div>
      <div className="field">
        <span>Timeouts per half</span>
        <div className="segmented" role="radiogroup" aria-label="Timeouts per half">
          {timeoutChoices.map((t) => (
            <button key={t} type="button" role="radio" aria-checked={t === timeouts} className={t === timeouts ? "on" : ""} onClick={() => onTimeouts(t)}>
              {t}
            </button>
          ))}
        </div>
      </div>
    </>
  );
}

/** A quick schedule event, e.g. a scrimmage that comes up at practice (_NewEventDialog). */
function NewEvent({
  teamId,
  tournament,
  title: initialTitle,
  day: initialDay,
  onDone,
}: {
  teamId: string;
  tournament: boolean;
  title: string;
  day: string;
  onDone: (e: LinkableEvent | null) => void;
}) {
  const { user } = useAuth();
  const [title, setTitle] = useState(initialTitle || (tournament ? "" : "Scrimmage"));
  const [type, setType] = useState(tournament ? "tournament" : "practice");
  const [day, setDay] = useState(initialDay);
  const [time, setTime] = useState(() => {
    const d = new Date();
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function add() {
    if (!user || !title.trim()) return;
    const [y, m, d] = day.split("-").map(Number);
    const [hh, mm] = time.split(":").map(Number);
    const startsAt = new Date(y, m - 1, d, hh, mm).toISOString();
    setBusy(true);
    setError("");
    try {
      const { id } = await callApi<SaveTeamEventResult>(user, apiUrl(teamId, "/events"), {
        method: "POST",
        body: { title: title.trim(), type, startsAt },
      });
      onDone({ id, title: title.trim(), type, startsAt, location: "" });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Couldn't add the event. Try again.");
      setBusy(false);
    }
  }

  return (
    <div className="card st-subcard">
      <h4 className="card-title">New schedule event</h4>
      <label className="field">
        <span>Event title</span>
        <input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={100} />
      </label>
      {!tournament && (
        <div className="segmented" role="radiogroup" aria-label="Event type">
          {(["practice", "game", "scrimmage", "other"] as const).map((t) => (
            <button key={t} type="button" role="radio" aria-checked={t === type} className={t === type ? "on" : ""} onClick={() => setType(t)}>
              {typeLabel[t]}
            </button>
          ))}
        </div>
      )}
      <div className="form-row">
        <label className="field">
          <span>Day</span>
          <input type="date" value={day} onChange={(e) => e.target.value && setDay(e.target.value)} />
        </label>
        <label className="field">
          <span>Time</span>
          <input type="time" value={time} onChange={(e) => e.target.value && setTime(e.target.value)} />
        </label>
      </div>
      {error && <p className="form-error">{error}</p>}
      <div className="form-actions">
        <button type="button" className="btn btn-small" onClick={() => onDone(null)}>
          Cancel
        </button>
        <button type="button" className="btn btn-small btn-primary" disabled={!title.trim() || busy} onClick={add}>
          Add to schedule
        </button>
      </div>
    </div>
  );
}
