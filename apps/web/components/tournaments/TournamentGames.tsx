"use client";
// A hosted tournament's Schedule and Results (Standings for a league)
// tabs, by division: publishing the schedule, the games with score
// reporting and confirming for captains and final scores for the host,
// pool standings, the bracket and final places.
import {
  awaitingSeeds,
  bracketSeeds,
  byesIn,
  type EngineGame,
  formatOf,
  hasTeams,
  isBracketStage,
  isDone,
  laterGamesPlayed,
  ordinal,
  placementsOf,
  planEndsAt,
  poolTeams,
  ScheduleError,
  type SchedulePlan,
  scheduleFor,
  scoreError,
  scoreLabel,
  seasonFor,
  skippedGame,
  standings,
  suggestedFormat,
  tournamentFormatLabels,
  engineSeason,
  engineSettings,
  divisionLabel,
  createdLeagueTeamPrefix,
  pointDiff,
} from "@stall10/shared";
import { type FormEvent, useState } from "react";
import { type TournamentState, divisionPath, useAction } from "./useTournament";

const dayLabel = (d: Date) => d.toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" });
const timeLabel = (d: Date) => d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });

/** The schedule a division would get now, or why it can't have one (preview). */
export function previewPlan(s: TournamentState): { plan: SchedulePlan | null; problem: string | null } {
  const t = s.t;
  const d = s.division;
  if (!t || !d) return { plan: null, problem: "Add a division first." };
  const drafted = d.teams ?? [];
  const created = drafted.length > 0 && drafted.every((x) => x.id.startsWith(createdLeagueTeamPrefix));
  const mixed = t.entryType === "players" && t.teamEntry === true;
  if (t.kind === "league" && t.entryType === "players" && !created && (drafted.length > 0 || !mixed)) {
    return { plan: null, problem: "Create the league's teams first: on the Players tab, draft teams, then Create teams." };
  }
  try {
    const settings = engineSettings(d.settings);
    const season = engineSeason(t.season);
    const plan = t.kind === "league" && season ? seasonFor(d.seeds, settings, season) : scheduleFor(d.seeds, settings);
    return { plan, problem: null };
  } catch (e) {
    if (e instanceof ScheduleError) return { plan: null, problem: e.message };
    throw e;
  }
}

/** "Winner of game 5", "Pool A #1" or the team's name (slotLabel). */
function slotLabel(s: TournamentState, g: EngineGame, a: boolean): string {
  const team = a ? g.teamA : g.teamB;
  if (team) return s.teamName(team);
  const src = a ? g.sourceA : g.sourceB;
  const number = (id: string) => {
    const x = s.games.find((y) => y.id === id);
    return x ? String(x.order + 1) : "?";
  };
  if (!src) return "TBD";
  if (src.type === "pool") return `Pool ${src.pool} #${src.rank}`;
  return `${src.type === "winner" ? "Winner" : "Loser"} of game ${number(src.game)}`;
}

type Action = "report" | "confirm" | "awaiting" | null;
function actionFor(s: TournamentState, g: EngineGame): Action {
  if (!hasTeams(g) || isDone(g)) return null;
  const mineA = s.captainOf.has(g.teamA ?? "");
  const mineB = s.captainOf.has(g.teamB ?? "");
  if (!mineA && !mineB) return null;
  if (g.status !== "reported" || !g.report) return "report";
  return g.report.byTeam === (mineA ? g.teamA : g.teamB) ? "awaiting" : "confirm";
}
const badge: Record<Exclude<Action, null>, string> = { report: "Report score", confirm: "Confirm score", awaiting: "Waiting for the other captain" };

function ScoreForm({ s, g, mode, onDone }: { s: TournamentState; g: EngineGame; mode: "report" | "final"; onDone: () => void }) {
  const [a, setA] = useState(String(g.scoreA ?? g.report?.scoreA ?? ""));
  const [b, setB] = useState(String(g.scoreB ?? g.report?.scoreB ?? ""));
  const { busy, error, setError, run } = useAction();
  const url = `${divisionPath(s.id, s.divisionId ?? "")}/games/${encodeURIComponent(g.id)}`;
  async function submit(e: FormEvent) {
    e.preventDefault();
    const scoreA = a === "" ? null : Number(a);
    const scoreB = b === "" ? null : Number(b);
    const why = scoreError(scoreA, scoreB);
    if (why) return setError(why);
    const r = mode === "report" ? await run(`${url}/report`, "POST", { scoreA, scoreB }) : await run(`${url}/score`, "PUT", { scoreA, scoreB });
    if (r.ok) onDone();
  }
  return (
    <form className="settings-form hosted-score-form" onSubmit={submit}>
      <div className="form-grid">
        <label>
          {slotLabel(s, g, true)}
          <input type="number" min={0} max={99} inputMode="numeric" value={a} onChange={(e) => setA(e.target.value)} />
        </label>
        <label>
          {slotLabel(s, g, false)}
          <input type="number" min={0} max={99} inputMode="numeric" value={b} onChange={(e) => setB(e.target.value)} />
        </label>
      </div>
      <small className="muted">{mode === "report" ? "The other captain confirms it before it counts." : "As the host, this is final right away."}</small>
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions">
        <button className="btn btn-primary btn-small" disabled={busy}>
          {mode === "report" ? "Report score" : isDone(g) ? "Correct the score" : "Set final score"}
        </button>
        <button type="button" className="text-btn" onClick={onDone}>
          Cancel
        </button>
      </div>
    </form>
  );
}

/** One game: its teams and score, and what the viewer can do with it. */
export function GameCard({ s, g }: { s: TournamentState; g: EngineGame }) {
  const [open, setOpen] = useState<"report" | "final" | null>(null);
  const { busy, error, run } = useAction();
  const action = actionFor(s, g);
  const skipped = skippedGame(g, s.games);
  const canSet = s.manager && hasTeams(g) && !laterGamesPlayed(g, s.games);
  const winner = isDone(g) ? ((g.scoreA ?? 0) > (g.scoreB ?? 0) ? "a" : "b") : null;
  const r = g.report;
  const url = `${divisionPath(s.id, s.divisionId ?? "")}/games/${encodeURIComponent(g.id)}`;
  return (
    <div className={`hosted-game${action === "report" || action === "confirm" ? " hosted-game-you" : ""}${skipped ? " hosted-game-skipped" : ""}`}>
      <div className="hosted-game-head">
        <small className="muted">
          Game {g.order + 1} · {g.label}
          {g.startsAt ? ` · ${timeLabel(g.startsAt)}` : ""} · Field {g.field}
        </small>
        {action && <span className="pill">{badge[action]}</span>}
      </div>
      <div className="hosted-game-teams">
        <span className={winner === "a" ? "hosted-winner" : ""}>{slotLabel(s, g, true)}</span>
        <b>{isDone(g) ? g.scoreA : ""}</b>
        <span className={winner === "b" ? "hosted-winner" : ""}>{slotLabel(s, g, false)}</span>
        <b>{isDone(g) ? g.scoreB : ""}</b>
      </div>
      {skipped && <small className="muted">Not needed: the winners&apos; bracket champion won the final.</small>}
      {r && !isDone(g) && (
        <small className="muted">
          {s.teamName(r.byTeam)} reported {slotLabel(s, g, true)} {r.scoreA}, {slotLabel(s, g, false)} {r.scoreB}.
        </small>
      )}
      {open ? (
        <ScoreForm s={s} g={g} mode={open} onDone={() => setOpen(null)} />
      ) : (
        (action || canSet) && (
          <div className="home-actions hosted-game-actions">
            {action === "report" && (
              <button type="button" className="btn btn-primary btn-small" onClick={() => setOpen("report")}>
                Report score
              </button>
            )}
            {action === "confirm" && r && (
              <>
                <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={() => void run(`${url}/confirm`, "POST")}>
                  Confirm {r.scoreA}–{r.scoreB}
                </button>
                <button type="button" className="btn btn-small" onClick={() => setOpen("report")}>
                  That&apos;s not right
                </button>
              </>
            )}
            {canSet && (
              <button type="button" className="text-btn" onClick={() => setOpen("final")}>
                {isDone(g) ? "Correct the score" : "Set final score"}
              </button>
            )}
          </div>
        )
      )}
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}

/** Generate and publish (or regenerate) the selected division's games. */
function PublishCard({ s }: { s: TournamentState }) {
  const { plan, problem } = previewPlan(s);
  const { busy, error, run } = useAction();
  const d = s.division;
  const t = s.t;
  if (!d || !t) return null;
  const played = s.games.some((g) => g.status !== "scheduled");
  async function publish() {
    if (!plan || !d) return;
    if (s.published && !window.confirm(played ? "Regenerate the schedule? Scores already entered are lost: every game is regenerated from the current seeds." : "Regenerate the schedule? Every game is regenerated from the current seeds.")) return;
    await run(`${divisionPath(s.id, d.id)}/schedule`, "PUT", {
      games: plan.games.map((g) => ({
        id: g.id,
        order: g.order,
        stage: g.stage,
        round: g.round,
        label: g.label,
        pool: g.pool,
        field: g.field,
        startsAt: g.startsAt?.toISOString() ?? null,
        teamA: g.teamA,
        teamB: g.teamB,
        sourceA: g.sourceA,
        sourceB: g.sourceB,
        ifNeeded: g.ifNeeded,
        ...(g.place != null && { place: g.place }),
      })),
    });
  }
  const end = plan ? planEndsAt(plan) : null;
  return (
    <section className="card">
      <h2 className="card-title">{s.published ? "Schedule published" : "Schedule"}</h2>
      {plan ? (
        <p>
          {d.seeds.length} teams · {plan.games.length} games
          {d.settings.format !== "roundRobin" && (d.settings.format === "poolsSingleElim" || d.settings.format === "poolsPlacement") && t.kind !== "league" ? ` · ${d.settings.poolCount} pools` : ""}
          <br />
          <small className="muted">
            {plan.days.map((day) => `${day.startsAt.toLocaleDateString("en-US", { weekday: "short" })} ${timeLabel(day.startsAt)}–${timeLabel(day.endsAt)}`).join(" · ")}
            {end ? "" : ""}
          </small>
        </p>
      ) : (
        <p className="muted">{problem ?? (t.entryType === "players" ? "Draft and save at least two teams first." : "Accept at least two teams first.")}</p>
      )}
      {t.kind !== "league" && d.seeds.length >= 2 && d.settings.format !== suggestedFormat(d.seeds.length) && (
        <p className="muted small">
          Tip: for {d.seeds.length} teams, {tournamentFormatLabels[suggestedFormat(d.seeds.length)].label.toLowerCase()} usually works best.
        </p>
      )}
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions">
        <button type="button" className={`btn btn-small ${s.published && played ? "btn-danger" : "btn-primary"}`} disabled={!plan || busy} onClick={() => void publish()}>
          {s.published ? "Regenerate schedule" : "Publish schedule"}
        </button>
      </div>
    </section>
  );
}

export function DivisionPicker({ s }: { s: TournamentState }) {
  if (s.divisions.length < 2) return null;
  return (
    <div className="segmented hosted-divisions" role="group" aria-label="Division">
      {s.divisions.map((d) => (
        <button key={d.id} type="button" className={d.id === s.divisionId ? "on" : ""} onClick={() => s.selectDivision(d.id)}>
          {divisionLabel(d)}
        </button>
      ))}
    </div>
  );
}

export function NoDivisions({ s }: { s: TournamentState }) {
  return <p className="empty">{s.manager ? "No divisions yet. Open one under Edit details." : "The host is still setting up divisions."}</p>;
}

export function ScheduleTab({ s }: { s: TournamentState }) {
  const d = s.division;
  const { busy, error, run } = useAction();
  if (!d || !s.t) return <NoDivisions s={s} />;
  const league = s.t.kind === "league";
  const canSeed = s.manager && bracketSeeds(s.games).length > 0;
  let lastDay = "";
  return (
    <div className="stack">
      <DivisionPicker s={s} />
      <p className="muted">
        {divisionLabel(d)} · {league ? "Weekly" : tournamentFormatLabels[d.settings.format]?.label} · {scoreLabel(d.settings)} · {d.settings.fields} {d.settings.fields === 1 ? "field" : "fields"}
      </p>
      {s.manager && <PublishCard s={s} />}
      {canSeed && (
        <div className="home-actions">
          <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={() => void run(`${divisionPath(s.id, d.id)}/seed-bracket`, "POST")}>
            Pools are done: seed the bracket
          </button>
        </div>
      )}
      {error && <p className="form-error">{error}</p>}
      {s.myUpcoming.length > 0 && (
        <section className="stack">
          <h3 className="hosted-heading">Your next games</h3>
          {s.myUpcoming.slice(0, 3).map((g) => (
            <GameCard key={g.id} s={s} g={g} />
          ))}
        </section>
      )}
      {s.games.length === 0 && !s.manager && <p className="empty">The schedule appears here once the host publishes it.</p>}
      {s.games.length > 0 && <h3 className="hosted-heading">All games</h3>}
      {s.games.map((g) => {
        const day = g.startsAt ? g.startsAt.toDateString() : "";
        const head = day && day !== lastDay;
        lastDay = day || lastDay;
        const byes = league && g.stage === "pool" && head ? byesIn(d.seeds, s.games, g.round) : [];
        return (
          <div key={g.id} className="stack hosted-game-row">
            {head && g.startsAt && (
              <div>
                <h4 className="hosted-day">{league ? `${g.stage === "pool" ? `Week ${g.round}` : "Playoffs"} · ${dayLabel(g.startsAt)}` : dayLabel(g.startsAt)}</h4>
                {byes.length > 0 && <small className="muted">Bye: {byes.map(s.teamName).join(", ")}</small>}
              </div>
            )}
            <GameCard s={s} g={g} />
          </div>
        );
      })}
    </div>
  );
}

export function ResultsTab({ s }: { s: TournamentState }) {
  const d = s.division;
  if (!d || !s.t) return <NoDivisions s={s} />;
  const league = s.t.kind === "league";
  const places = d.placements.length > 0 ? d.placements : placementsOf(formatOf(s.t, d), d.seeds, s.games);
  const pools = poolTeams(s.games);
  const columns = new Map<string, EngineGame[]>();
  for (const g of s.games.filter((x) => isBracketStage(x.stage))) {
    const key = `${g.stage}:${g.round}`;
    columns.set(key, [...(columns.get(key) ?? []), g]);
  }
  return (
    <div className="stack">
      <DivisionPicker s={s} />
      {s.games.length === 0 && <p className="empty">Results show up here once games are played.</p>}
      {places.length > 0 && (
        <>
          <section className="card hosted-champion">
            <b>{s.teamName(places[0])}</b>
            <span className="muted">{divisionLabel(d)} champion</span>
          </section>
          <section className="card">
            <h2 className="card-title">Final standings</h2>
            <table className="data-table">
              <tbody>
                {places.map((id, i) => (
                  <tr key={id}>
                    <td className="narrow">{ordinal(i + 1)}</td>
                    <td>{s.teamName(id)}</td>
                    <td className="narrow muted">{d.seeds.includes(id) ? `Seed ${d.seeds.indexOf(id) + 1}` : ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>
        </>
      )}
      {pools.size > 0 && (
        <section className="card">
          <h2 className="card-title">{league ? "Standings" : "Pools"}</h2>
          {[...pools.entries()].map(([pool, teams]) => (
            <div key={pool} className="hosted-table-wrap">
              {pools.size > 1 && <h3 className="hosted-heading">Pool {pool}</h3>}
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Team</th>
                    <th className="narrow">W</th>
                    <th className="narrow">L</th>
                    <th className="narrow">+/−</th>
                    <th className="narrow">PF</th>
                  </tr>
                </thead>
                <tbody>
                  {standings(teams, s.games.filter((g) => g.pool === pool)).map((row) => (
                    <tr key={row.teamId}>
                      <td>{s.teamName(row.teamId)}</td>
                      <td className="narrow">{row.wins}</td>
                      <td className="narrow">{row.losses}</td>
                      <td className="narrow">{pointDiff(row) > 0 ? `+${pointDiff(row)}` : pointDiff(row)}</td>
                      <td className="narrow">{row.pointsFor}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ))}
          {awaitingSeeds(s.games) && <p className="muted small">The bracket fills from these once every pool game is in.</p>}
        </section>
      )}
      {columns.size > 0 && (
        <section className="card">
          <h2 className="card-title">Bracket</h2>
          <div className="hosted-bracket">
            {[...columns.values()].map((games) => (
              <div key={`${games[0].stage}${games[0].round}`} className="hosted-bracket-col">
                <h3 className="hosted-heading">{new Set(games.map((g) => g.label)).size === 1 ? games[0].label : `Round ${games[0].round}`}</h3>
                {games.map((g) => (
                  <GameCard key={g.id} s={s} g={g} />
                ))}
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
