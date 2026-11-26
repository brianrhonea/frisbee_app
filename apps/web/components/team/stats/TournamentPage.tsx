"use client";
import {
  type CreatedId,
  gameWon,
  lineSize,
  type SaveStatsGameRequest,
  SaveQueue,
  type StatLine,
  type StatsPlayer,
  type StatsTournament,
  sideShort,
  statSheetOfGames,
  statsTournamentBody,
} from "@stall10/shared";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useRef, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useAuth } from "../../AuthProvider";
import { useTeamHub } from "../TeamContext";
import { apiUrl, gameUrl, nameMap, statsAccess, useStatsGames, useStatsPlayers, useStatsTournaments } from "./data";
import { LinePicker } from "./LinePicker";
import { GameSettings } from "./NewStatsForm";
import { BackToStats, StatsGate } from "./SeasonStatsPage";
import { StatSheetTable } from "./StatSheetTable";
import { confirmAndDelete, deleteGameMessage, GameRow } from "./StatsHome";
import "./stats.css";
import { formatDate } from "@/lib/dates";
import { SegmentedTabs } from "../../ui/SegmentedTabs";

const newId = () => (typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now().toString(36)}${Math.random().toString(36).slice(2)}`);

/** A tournament folder (TournamentScreen): its games in order, who's attending, its lines, its stats. */
export function TournamentPage({ tournamentId }: { tournamentId: string }) {
  return (
    <StatsGate>
      <Tournament tournamentId={tournamentId} />
    </StatsGate>
  );
}

function Tournament({ tournamentId }: { tournamentId: string }) {
  const { teamId, viewer } = useTeamHub();
  const { user } = useAuth();
  const router = useRouter();
  const access = statsAccess(viewer);
  const tournaments = useStatsTournaments(teamId);
  const games = useStatsGames(teamId);
  const players = useStatsPlayers(teamId);
  const [tab, setTab] = useState<"games" | "roster" | "stats">("games");
  const [local, setLocal] = useState<StatsTournament | null>(null);
  const [adding, setAdding] = useState(false);
  const [error, setError] = useState("");
  const userRef = useRef(user);
  userRef.current = user;

  // Saves go one at a time, newest first, at most one a second.
  const queue = useMemo(
    () =>
      new SaveQueue<StatsTournament>(
        async (t) => {
          if (!userRef.current) throw new Error("Signed out");
          await callApi(userRef.current, apiUrl(teamId, `/stats-tournaments/${encodeURIComponent(t.id)}`), { method: "PUT", body: statsTournamentBody(t) });
        },
        (e) => setError(e === null ? "" : problem(e, "Couldn't save the tournament. It will retry.")),
      ),
    [teamId],
  );
  useEffect(() => () => queue.flush(), [queue]);

  const live = tournaments.data?.find((t) => t.id === tournamentId);
  // The listener's copy, unless this page has a change of its own still saving.
  const t = local && queue.dirty ? local : (live ?? null);

  if (tournaments.error ?? games.error) return <p className="form-error">{tournaments.error ?? games.error}</p>;
  if (!tournaments.data || !games.data) return <p className="muted" aria-busy="true">Loading…</p>;
  if (!t) {
    return (
      <div className="stack">
        <BackToStats teamId={teamId} />
        <p className="empty">Tournament not found.</p>
      </div>
    );
  }

  const its = games.data.filter((g) => g.tournamentId === tournamentId).reverse();
  const all = players.data ?? [];
  const rosterIds = new Set(t.roster);
  const roster = all.filter((p) => rosterIds.has(p.id));
  const wins = its.filter((g) => gameWon(g) === true).length;
  const losses = its.filter((g) => gameWon(g) === false).length;
  const nameOf = nameMap(players.data);
  const team = statSheetOfGames(its).team;
  const pct = (v: number | null) => (v === null ? "–" : `${Math.round(v * 100)}%`);

  const update = (change: (x: StatsTournament) => StatsTournament) => {
    if (!access.keepStats) return;
    const next = change(t);
    setLocal(next);
    queue.schedule(next, true);
  };

  return (
    <div className="stack">
      <BackToStats teamId={teamId} />
      <div className="st-game-head">
        <div>
          <h2 className="card-title">{t.name}</h2>
          <p className="muted small">{[formatDate(t.startDate, { month: "short", day: "numeric", year: "numeric" }), ...(t.location ? [t.location] : []), `${wins}–${losses}`].join(" · ")}</p>
        </div>
        <div className="home-actions">
          {access.keepStats && (
            <button type="button" className="btn btn-primary btn-small" onClick={() => setAdding(true)}>
              Add game
            </button>
          )}
          {access.canDelete && user && (
            <button
              type="button"
              className="btn btn-small"
              onClick={async () => {
                const ok = await confirmAndDelete(
                  user,
                  apiUrl(teamId, `/stats-tournaments/${encodeURIComponent(t.id)}`),
                  `Delete ${t.name}?\n\nThis permanently deletes the tournament, its roster and lines, and ${its.length === 1 ? "its game" : `all ${its.length} of its games`} with every stat in them.`,
                  setError,
                );
                if (ok) router.push(`/teams/${encodeURIComponent(teamId)}/stats`);
              }}
            >
              Delete tournament
            </button>
          )}
        </div>
      </div>
      {adding && <AddGame teamId={teamId} tournament={t} onClose={() => setAdding(false)} />}
      {/* The tournament at a glance (the app's summary). */}
      <section className="card st-numbers st-glance">
        <div>
          <b>
            {wins}–{losses}
          </b>
          <small>Record</small>
        </div>
        <div>
          <b>{pct(team.oEfficiency)}</b>
          <small>O efficiency</small>
        </div>
        <div>
          <b>{pct(team.breakRate)}</b>
          <small>Break rate</small>
        </div>
      </section>
      {error && <p className="form-error">{error}</p>}
      <SegmentedTabs
        variant="underline"
        label="Tournament"
        items={[
          { id: "games", label: "Games" },
          { id: "roster", label: "Roster & lines" },
          { id: "stats", label: "Stats" },
        ]}
        value={tab}
        onChange={(k) => setTab(k as typeof tab)}
      />
      {tab === "games" &&
        (its.length === 0 ? (
          <p className="empty">No games yet. Add a game to start tracking stats.</p>
        ) : (
          <ol className="game-list st-rounds">
            {its.map((g) => (
              <GameRow
                key={g.id}
                teamId={teamId}
                game={g}
                onDelete={
                  access.canDelete && user
                    ? () => void confirmAndDelete(user, apiUrl(teamId, `/stats-games/${encodeURIComponent(g.id)}`), deleteGameMessage(g), setError)
                    : undefined
                }
              />
            ))}
          </ol>
        ))}
      {tab === "roster" && (
        <RosterAndLines
          t={t}
          canEdit={access.keepStats}
          all={all}
          roster={roster}
          nameOf={nameOf}
          onRoster={(ids) => update((x) => ({ ...x, roster: ids, lines: x.lines.filter((l) => l.players.every((p) => ids.includes(p))) }))}
          onSaveLine={(name, ids, side, id) => {
            const line: StatLine = { id: id ?? newId(), name, players: ids, side };
            update((x) => ({ ...x, lines: id === undefined ? [...x.lines, line] : x.lines.map((l) => (l.id === id ? line : l)) }));
          }}
          onDeleteLine={(id) => update((x) => ({ ...x, lines: x.lines.filter((l) => l.id !== id) }))}
        />
      )}
      {tab === "stats" && <StatSheetTable sheet={statSheetOfGames(its)} nameOf={nameOf} />}
    </div>
  );
}

function RosterAndLines({
  t,
  canEdit,
  all,
  roster,
  nameOf,
  onRoster,
  onSaveLine,
  onDeleteLine,
}: {
  t: StatsTournament;
  canEdit: boolean;
  all: StatsPlayer[];
  roster: StatsPlayer[];
  nameOf: (id: string) => string;
  onRoster: (ids: string[]) => void;
  onSaveLine: (name: string, ids: string[], side: StatLine["side"], id?: string) => void;
  onDeleteLine: (id: string) => void;
}) {
  const [picking, setPicking] = useState<Set<string> | null>(null);
  const [editing, setEditing] = useState<StatLine | "new" | null>(null);
  return (
    <div className="stack">
      <div className="st-row">
        <h3 className="card-title">Tournament roster ({roster.length})</h3>
        {canEdit && !picking && (
          <button type="button" className="text-btn" onClick={() => setPicking(new Set(t.roster))}>
            Edit
          </button>
        )}
      </div>
      {picking ? (
        <div className="card st-subcard">
          <h4 className="card-title">Who&apos;s attending? ({picking.size})</h4>
          <div className="st-chooser">
            {all.map((p) => {
              const on = picking.has(p.id);
              return (
                <button
                  key={p.id}
                  type="button"
                  className={`st-chip${on ? " on" : ""}`}
                  aria-pressed={on}
                  onClick={() =>
                    setPicking((s) => {
                      const n = new Set(s);
                      if (!n.delete(p.id)) n.add(p.id);
                      return n;
                    })
                  }
                >
                  <b>{p.number ?? "–"}</b> {p.name}
                </button>
              );
            })}
          </div>
          <div className="form-actions">
            <button type="button" className="text-btn" onClick={() => setPicking(new Set(all.map((p) => p.id)))}>
              Select all
            </button>
            <button type="button" className="btn btn-small" onClick={() => setPicking(null)}>
              Cancel
            </button>
            <button
              type="button"
              className="btn btn-small btn-primary"
              onClick={() => {
                onRoster(all.filter((p) => picking.has(p.id)).map((p) => p.id));
                setPicking(null);
              }}
            >
              Save
            </button>
          </div>
        </div>
      ) : (
        <>
          {roster.length < lineSize && <p className="form-error small">Add at least {lineSize} players to build lines.</p>}
          <ul className="st-chips st-plain">
            {roster.map((p) => (
              <li key={p.id} className="st-chip">
                <b>{p.number ?? "–"}</b> {p.name}
              </li>
            ))}
          </ul>
        </>
      )}
      <div className="st-row">
        <h3 className="card-title">Lines</h3>
        {canEdit && (
          <button type="button" className="text-btn" disabled={roster.length < lineSize} onClick={() => setEditing("new")}>
            New line
          </button>
        )}
      </div>
      {editing && (
        <LinePicker
          title={editing === "new" ? "New line" : `Edit ${editing.name}`}
          available={roster}
          initial={editing === "new" ? [] : editing.players}
          requireName
          defaultName={editing === "new" ? "" : editing.name}
          defaultSide={editing === "new" ? null : editing.side}
          onDone={(c) => {
            const was = editing;
            setEditing(null);
            if (c) onSaveLine(c.saveAs ?? (was === "new" ? "Line" : was.name), c.players, c.side, was === "new" ? undefined : was.id);
          }}
        />
      )}
      {t.lines.length === 0 ? (
        <p className="empty">No lines yet.</p>
      ) : (
        <ul className="game-list">
          {t.lines.map((l) => (
            <li key={l.id} className="card st-row">
              <span>
                <b>
                  {l.side ? `${sideShort[l.side]} · ` : ""}
                  {l.name}
                </b>
                <small className="muted"> {l.players.map(nameOf).join(", ")}</small>
              </span>
              {canEdit && (
                <span>
                  <button type="button" className="text-btn" onClick={() => setEditing(l)}>
                    Edit
                  </button>
                  <button type="button" className="text-btn st-danger" onClick={() => onDeleteLine(l.id)}>
                    Delete
                  </button>
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/** A game in the tournament, dated now (TournamentViewModel._addGame). */
function AddGame({ teamId, tournament, onClose }: { teamId: string; tournament: StatsTournament; onClose: () => void }) {
  const { user } = useAuth();
  const router = useRouter();
  const [opponent, setOpponent] = useState("");
  const [gameTo, setGameTo] = useState(15);
  const [timeouts, setTimeouts] = useState(2);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  return (
    <form
      className="card settings-form st-new"
      onSubmit={async (e) => {
        e.preventDefault();
        if (!user || !opponent.trim() || busy) return;
        setBusy(true);
        setError("");
        const body: SaveStatsGameRequest = {
          opponent: opponent.trim(),
          date: new Date().toISOString(),
          gameTo,
          timeoutsPerHalf: timeouts,
          tournamentId: tournament.id,
          eventId: tournament.eventId,
        };
        try {
          const { id } = await callApi<CreatedId>(user, apiUrl(teamId, "/stats-games"), { method: "POST", body });
          router.push(gameUrl(teamId, id));
        } catch (err) {
          setError(problem(err, "Couldn't add the game. Try again."));
          setBusy(false);
        }
      }}
    >
      <h3 className="card-title">Add game</h3>
      <label className="field">
        <span>Opponent</span>
        <input autoFocus value={opponent} maxLength={100} onChange={(e) => setOpponent(e.target.value)} />
      </label>
      <GameSettings gameTo={gameTo} timeouts={timeouts} onGameTo={setGameTo} onTimeouts={setTimeouts} />
      {error && <p className="form-error">{error}</p>}
      <div className="form-actions">
        <button type="button" className="btn btn-small" onClick={onClose}>
          Cancel
        </button>
        <button type="submit" className="btn btn-small btn-primary" disabled={!opponent.trim() || busy}>
          Add
        </button>
      </div>
    </form>
  );
}
