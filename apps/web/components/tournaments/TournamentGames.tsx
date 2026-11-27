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
  leagueTeamPrefix,
  pointDiff,
  currentWeekIndex,
  leagueNights,
  leagueWeekLabel,
  leagueWeeks,
} from "@stall10/shared";
import { type FormEvent, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { Dialog } from "@/components/Dialog";
import { dayKey, useRenderZone } from "@/lib/renderZone";
import { type TournamentState, divisionPath, useAction } from "./useTournament";
import { StatusPill } from "../ui/StatusPill";
import { useConfirm } from "@/components/ui/ConfirmDialog";
import { ErrorNote } from "@/components/StatusViews";

// In [zone] (useRenderZone: UTC while a server-rendered page hydrates), else the viewer's.
const dayLabel = (d: Date, zone?: string) => d.toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric", timeZone: zone });
const timeLabel = (d: Date, zone?: string) => d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", timeZone: zone });

/** The schedule a division would get now, or why it can't have one (preview). */
export function previewPlan(s: TournamentState): { plan: SchedulePlan | null; problem: string | null } {
  return planFor(s.t, s.division);
}

/** [d]'s schedule as it would be published now (the run sheet plans every division at once). */
export function planFor(t: TournamentState["t"], d: TournamentState["division"]): { plan: SchedulePlan | null; problem: string | null } {
  if (!t || !d) return { plan: null, problem: "Add a division first." };
  const drafted = d.teams ?? [];
  const created = drafted.length > 0 && drafted.every((x) => x.id.startsWith(leagueTeamPrefix));
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

/** A team's initials in a small square (the app's team mark). */
export function TeamMark({ name }: { name: string }) {
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() ?? "")
    .join("");
  return (
    <span className="hosted-mark" aria-hidden>
      {initials || "?"}
    </span>
  );
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

/**
 * One team's score in the score form: its name, then −, the score in the
 * scoreboard face (still typed straight in) and + (ScoreStepper in the
 * app). An untouched score stays empty, so "Enter both scores." still
 * shows; + starts it at 1, and the steppers keep it from 0 to 99.
 */
export function ScoreStepper({ name, value, onChange }: { name: string; value: string; onChange: (v: string) => void }) {
  const n = value.trim() === "" ? null : Number(value);
  const step = (by: number) => onChange(String(Math.min(99, Math.max(0, (n != null && Number.isFinite(n) ? n : 0) + by))));
  return (
    <div className="score-step">
      <span className="score-step-name">{name}</span>
      <div className="score-step-row">
        <button type="button" className="btn score-step-btn" aria-label={`One less for ${name}`} title={`One less for ${name}`} disabled={n == null || !(n > 0)} onClick={() => step(-1)}>
          −
        </button>
        <input
          type="number"
          className="score-step-input"
          min={0}
          max={99}
          inputMode="numeric"
          placeholder="–"
          aria-label={`Score for ${name}`}
          value={value}
          onChange={(e) => onChange(e.target.value)}
        />
        <button type="button" className="btn btn-primary score-step-btn" aria-label={`One more for ${name}`} title={`One more for ${name}`} disabled={n != null && n >= 99} onClick={() => step(1)}>
          +
        </button>
      </div>
    </div>
  );
}

/** [g]'s score form; it starts from the game's score, its report, else its running score. [onSent] (else [onDone]) once it's sent. */
function ScoreForm({ s, g, mode, onDone, onSent }: { s: TournamentState; g: EngineGame; mode: "report" | "final"; onDone: () => void; onSent?: () => void }) {
  const running = s.liveOf(g);
  const [a, setA] = useState(String(g.scoreA ?? g.report?.scoreA ?? running?.scoreA ?? ""));
  const [b, setB] = useState(String(g.scoreB ?? g.report?.scoreB ?? running?.scoreB ?? ""));
  const { busy, error, setError, run } = useAction();
  const url = `${divisionPath(s.id, s.divisionId ?? "")}/games/${encodeURIComponent(g.id)}`;
  async function submit(e: FormEvent) {
    e.preventDefault();
    const scoreA = a === "" ? null : Number(a);
    const scoreB = b === "" ? null : Number(b);
    const why = scoreError(scoreA, scoreB);
    if (why) return setError(why);
    const r = mode === "report" ? await run(`${url}/report`, "POST", { scoreA, scoreB }) : await run(`${url}/score`, "PUT", { scoreA, scoreB });
    if (r.ok) (onSent ?? onDone)();
  }
  return (
    <form className="settings-form hosted-score-form" onSubmit={submit}>
      <div className="score-steps">
        <ScoreStepper name={slotLabel(s, g, true)} value={a} onChange={setA} />
        <ScoreStepper name={slotLabel(s, g, false)} value={b} onChange={setB} />
      </div>
      <small className="muted">{mode === "report" ? "The other captain confirms it before it counts." : "As the host, this is final right away."}</small>
      {error && <ErrorNote>{error}</ErrorNote>}
      <div className="home-actions">
        <button className={`btn btn-small ${mode === "report" ? "hosted-btn-due" : "btn-primary"}`} disabled={busy}>
          {mode === "report" ? "Report score" : isDone(g) ? "Correct the score" : "Set final score"}
        </button>
        <button type="button" className="text-btn" onClick={onDone}>
          Cancel
        </button>
      </div>
    </form>
  );
}

/**
 * One game: its teams and score, and what the viewer can do with it.
 * [focus] (from a tournament-day card's Report score) scrolls to it and
 * opens the score form when it's the viewer's to report.
 */
export function GameCard({ s, g, focus = false }: { s: TournamentState; g: EngineGame; focus?: boolean }) {
  const zone = useRenderZone();
  const [open, setOpen] = useState<"report" | "final" | null>(null);
  const [keeping, setKeeping] = useState(false);
  const { busy, error, run } = useAction();
  const action = actionFor(s, g);
  const live = s.liveOf(g);
  const canKeep = action !== "confirm" && s.canKeepLive(g);
  const ref = useRef<HTMLDivElement>(null);
  const focused = useRef(false);
  useEffect(() => {
    if (!focus || focused.current || !action) return;
    focused.current = true;
    if (action === "report") setOpen("report");
    ref.current?.scrollIntoView({ block: "center" });
  }, [focus, action]);
  const skipped = skippedGame(g, s.games);
  const canSet = s.manager && hasTeams(g) && !laterGamesPlayed(g, s.games);
  const winner = isDone(g) ? ((g.scoreA ?? 0) > (g.scoreB ?? 0) ? "a" : "b") : null;
  const due = action === "report" || action === "confirm";
  const side = (a: boolean) => {
    const won = winner === (a ? "a" : "b");
    const name = slotLabel(s, g, a);
    return (
      <div className={`hosted-side${winner ? (won ? " hosted-winner" : " hosted-loser") : ""}`}>
        {(a ? g.teamA : g.teamB) ? <TeamMark name={name} /> : <span className="hosted-mark hosted-mark-tbd" aria-hidden />}
        <span className="hosted-side-name">{name}</span>
        <b className="hosted-score">{isDone(g) ? (a ? g.scoreA : g.scoreB) : live ? (a ? live.scoreA : live.scoreB) : ""}</b>
      </div>
    );
  };
  const r = g.report;
  const url = `${divisionPath(s.id, s.divisionId ?? "")}/games/${encodeURIComponent(g.id)}`;
  return (
    <div ref={ref} id={`game-${g.id}`} className={`hosted-game${due ? " hosted-game-you" : ""}${skipped ? " hosted-game-skipped" : ""}`}>
      {due && <b className="hosted-game-due">{action === "confirm" ? "Your game · confirm the score" : "Your game · needs a score"}</b>}
      <div className="hosted-game-head">
        <small>
          Game {g.order + 1} · {g.label}
          {g.startsAt ? ` · ${timeLabel(g.startsAt, zone)}` : ""} · Field {g.field}
        </small>
        <span className="hosted-game-pills">
          {live && <LivePill />}
          {action ? <StatusPill tone={due ? "attention" : "neutral"}>{badge[action]}</StatusPill> : isDone(g) && <StatusPill>Final</StatusPill>}
        </span>
      </div>
      <div className="hosted-game-teams">
        {side(true)}
        {side(false)}
      </div>
      {live && <small className="muted">Live score. It isn&apos;t final until it&apos;s reported.</small>}
      {skipped && <small className="muted">Not needed: the winners&apos; bracket champion won the final.</small>}
      {r && !isDone(g) && (
        <small className="muted">
          {s.teamName(r.byTeam)} reported {slotLabel(s, g, true)} {r.scoreA}, {slotLabel(s, g, false)} {r.scoreB}.
        </small>
      )}
      {open ? (
        <ScoreForm s={s} g={g} mode={open} onDone={() => setOpen(null)} />
      ) : (
        (action || canSet || canKeep) && (
          <div className="home-actions hosted-game-actions">
            {canKeep && (
              <button type="button" className="btn btn-small btn-primary" onClick={() => setKeeping(true)}>
                {live ? "Update live score" : "Start game"}
              </button>
            )}
            {action === "report" && (
              <button type="button" className="btn btn-small hosted-btn-due" onClick={() => setOpen("report")}>
                Report score
              </button>
            )}
            {action === "confirm" && r && (
              <>
                <button type="button" className="btn btn-small hosted-btn-due" disabled={busy} onClick={() => void run(`${url}/confirm`, "POST", { scoreA: r.scoreA, scoreB: r.scoreB })}>
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
      {error && <ErrorNote>{error}</ErrorNote>}
      {keeping && <LiveScoreDialog s={s} g={g} onClose={() => setKeeping(false)} />}
    </div>
  );
}

/** The red LIVE pill, only while a game is being played. */
export function LivePill() {
  return (
    <span className="hosted-live-pill hosted-live-small">
      <i aria-hidden />
      LIVE
    </span>
  );
}

/**
 * A game's running score while it's played (LiveScoreSheet in the app),
 * kept by its teams' captains or the host: Start game, then +1 for
 * whoever scores and − to undo. Everyone following sees it. It isn't
 * the final: Report final score (a captain) or Set final score (the host)
 * opens the score form, filled in from it.
 */
function LiveScoreDialog({ s, g: initial, onClose }: { s: TournamentState; g: EngineGame; onClose: () => void }) {
  const askConfirm = useConfirm();
  // The game as the page has it now (its listener keeps it current).
  const g = s.games.find((x) => x.id === initial.id) ?? initial;
  const [finalMode, setFinalMode] = useState<"report" | "final" | null>(null);
  const live = s.liveOf(g);
  const canKeep = s.canKeepLive(g);
  const action = actionFor(s, g);
  const captain = action === "report";
  const host = !captain && s.manager && hasTeams(g) && !laterGamesPlayed(g, s.games);
  const { error, stopping, setLive, stopLive, setError } = s.live;
  const nameA = slotLabel(s, g, true);
  const nameB = slotLabel(s, g, false);
  // Closing it clears a send's error.
  useEffect(() => () => setError(null), [setError]);
  const bump = (teamA: boolean, by: number) => {
    const a = live?.scoreA ?? 0;
    const b = live?.scoreB ?? 0;
    setLive(g.id, teamA ? a + by : a, teamA ? b : b + by);
  };
  async function stop() {
    if (!(await askConfirm({ message: "Stop the live score?\n\nThe running score comes off for everyone. Start again any time.", confirmLabel: "Stop", destructive: true }))) return;
    await stopLive(g.id);
  }
  const whyNot = !hasTeams(g)
    ? "Teams are decided by earlier games."
    : s.t?.status === "finished"
      ? "This event is over."
      : "Live scores are kept on the day the game is played.";
  const stepper = (a: boolean) => {
    const name = a ? nameA : nameB;
    const score = live ? (a ? live.scoreA : live.scoreB) : null;
    const on = canKeep && !!live;
    return (
      <div className="live-step">
        <TeamMark name={name} />
        <span className="live-step-name">{name}</span>
        <button type="button" className="btn live-step-btn" aria-label={`Undo a point for ${name}`} title={`Undo a point for ${name}`} disabled={!on || (score ?? 0) <= 0} onClick={() => bump(a, -1)}>
          −
        </button>
        <b className="live-step-score">{score ?? "–"}</b>
        <button type="button" className="btn btn-primary live-step-btn live-step-plus" aria-label={`Point for ${name}`} disabled={!on || (score ?? 0) >= 99} onClick={() => bump(a, 1)}>
          +1
        </button>
      </div>
    );
  };
  return (
    <Dialog label="Live score" onClose={onClose} className="card live-dialog" dismissOnBackdrop>
      <div className="live-dialog-head">
        <h2 className="card-title">Live score</h2>
        {live && <LivePill />}
      </div>
      <small className="muted">{[`Game ${g.order + 1}`, g.label, `Field ${g.field}`, s.division ? scoreLabel(s.division.settings) : null].filter(Boolean).join(" · ")}</small>
      {finalMode ? (
        <ScoreForm s={s} g={g} mode={finalMode} onDone={() => setFinalMode(null)} onSent={onClose} />
      ) : (
        <>
          <div className="live-steps" aria-live="polite">
            {stepper(true)}
            {stepper(false)}
          </div>
          {!live && (
            <button type="button" className="btn btn-primary" disabled={!canKeep || stopping} onClick={() => setLive(g.id, 0, 0)}>
              Start game
            </button>
          )}
          <p className="muted small live-note">{!canKeep && !live ? whyNot : "Everyone following sees this score. It isn't final until the score is reported and confirmed."}</p>
          {error && <ErrorNote>{error}</ErrorNote>}
          {(captain || host) && (
            <button type="button" className="btn hosted-btn-due" disabled={stopping} onClick={() => setFinalMode(captain ? "report" : "final")}>
              {captain ? "Report final score" : "Set final score"}
            </button>
          )}
          {live && canKeep && (
            <button type="button" className="text-btn live-stop" disabled={stopping} onClick={() => void stop()}>
              Stop live score
            </button>
          )}
          <div className="form-actions">
            <button type="button" className="btn btn-small" onClick={onClose}>
              Done
            </button>
          </div>
        </>
      )}
    </Dialog>
  );
}

/** Generate and publish (or regenerate) the selected division's games. */
function PublishCard({ s }: { s: TournamentState }) {
  const askConfirm = useConfirm();
  const { plan, problem } = previewPlan(s);
  const { busy, error, run } = useAction();
  const d = s.division;
  const t = s.t;
  if (!d || !t) return null;
  const played = s.games.some((g) => g.status !== "scheduled");
  async function publish() {
    if (!plan || !d) return;
    if (s.published && !(await askConfirm(played ? "Regenerate the schedule? Scores already entered are lost: every game is regenerated from the current seeds." : "Regenerate the schedule? Every game is regenerated from the current seeds."))) return;
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
  const pools = (d.settings.format === "poolsSingleElim" || d.settings.format === "poolsPlacement") && t.kind !== "league";
  const lastEnd = plan?.days.length ? plan.days[plan.days.length - 1].endsAt : null;
  return (
    <section className="card hosted-publish">
      <h2 className="card-title">{s.published ? "Schedule published" : plan ? "Schedule is ready to publish" : "Schedule"}</h2>
      {plan ? (
        <>
          <p>
            {d.seeds.length} teams{pools ? ` · ${d.settings.poolCount} pools` : ""}
            <br />
            <small className="muted">
              {plan.days.map((day) => `${day.startsAt.toLocaleDateString("en-US", { weekday: "short" })} ${timeLabel(day.startsAt)}–${timeLabel(day.endsAt)}`).join(" · ")}
            </small>
          </p>
          <div className="hosted-stats">
            <div className="hosted-stat">
              <b>{plan.games.length}</b>
              <span>Games</span>
            </div>
            <div className="hosted-stat">
              <b>{d.settings.fields}</b>
              <span>{d.settings.fields === 1 ? "Field" : "Fields"}</span>
            </div>
            {lastEnd && (
              <div className="hosted-stat">
                <b>{lastEnd.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" }).replace(/\s?[AP]M$/, "")}</b>
                <span>Last finish</span>
              </div>
            )}
          </div>
        </>
      ) : (
        <p className="muted">{problem ?? (t.entryType === "players" ? "Draft and save at least two teams first." : "Accept at least two teams first.")}</p>
      )}
      {t.kind !== "league" && d.seeds.length >= 2 && d.settings.format !== suggestedFormat(d.seeds.length) && (
        <p className="muted small">
          Tip: for {d.seeds.length} teams, {tournamentFormatLabels[suggestedFormat(d.seeds.length)].label.toLowerCase()} usually works best.
        </p>
      )}
      {error && <ErrorNote>{error}</ErrorNote>}
      <div className="home-actions">
        <button type="button" className={`btn btn-small ${s.published ? "" : "hosted-btn-due"}`} disabled={!plan || busy} onClick={() => void publish()}>
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

/** [focusGame]: a game to open first (?game=, from Report score). */
export function ScheduleTab({ s, focusGame }: { s: TournamentState; focusGame?: string }) {
  const d = s.division;
  const zone = useRenderZone();
  const { busy, error, run } = useAction();
  if (!d || !s.t) return <NoDivisions s={s} />;
  const league = s.t.kind === "league";
  const canSeed = s.manager && bracketSeeds(s.games).length > 0;
  const focused = focusGame ? (s.games.find((g) => g.id === focusGame) ?? null) : null;
  const upcoming = s.myUpcoming.filter((g) => g.id !== focused?.id).slice(0, 3);
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
      {error && <ErrorNote>{error}</ErrorNote>}
      {focused && (
        <section className="stack">
          <h3 className="hosted-heading">This game</h3>
          <GameCard s={s} g={focused} focus />
        </section>
      )}
      {upcoming.length > 0 && (
        <section className="stack">
          <h3 className="hosted-heading">Your next games</h3>
          {upcoming.map((g) => (
            <GameCard key={g.id} s={s} g={g} />
          ))}
        </section>
      )}
      {s.games.length === 0 && !s.manager && <p className="empty">The schedule appears here once the host publishes it.</p>}
      {s.games.length > 0 && <h3 className="hosted-heading">All games</h3>}
      {/* A league's season, a night at a time. */}
      {league && s.games.length > 0 && <LeagueWeeks key={d.id} s={s} />}
      {!league && s.games.map((g) => {
        const day = g.startsAt ? dayKey(g.startsAt, zone) : "";
        const head = day && day !== lastDay;
        lastDay = day || lastDay;
        return (
          <div key={g.id} className="stack hosted-game-row">
            {head && g.startsAt && <h4 className="hosted-day">{dayLabel(g.startsAt, zone)}</h4>}
            <GameCard s={s} g={g} />
          </div>
        );
      })}
    </div>
  );
}

/**
 * A league's games a night at a time (the app's _LeagueWeeks): "‹ Week 3 ›"
 * with the night's date and byes, then its games. Opens on tonight's
 * night, else the next one (the last once the season is over). Keyed by
 * division, so another division starts on its own current week.
 */
function LeagueWeeks({ s }: { s: TournamentState }) {
  const zone = useRenderZone();
  const [picked, setPicked] = useState<number | null>(null);
  const d = s.division;
  const weeks = leagueWeeks(s.games, (x) => dayKey(x, zone));
  if (!d || weeks.length === 0) return null;
  const i = Math.min(Math.max(picked ?? currentWeekIndex(weeks, dayKey(new Date(), zone)), 0), weeks.length - 1);
  const week = weeks[i];
  const rounds = new Set(week.games.filter((g) => g.stage === "pool").map((g) => g.round));
  const byes = [...new Set([...rounds].flatMap((r) => byesIn(d.seeds, s.games, r)))];
  const first = week.games[0]?.startsAt;
  return (
    <section className="stack league-weeks" aria-label="Schedule by week">
      <div className="league-week-nav">
        <button type="button" className="icon-btn league-week-arrow" aria-label="Previous week" title="Previous week" disabled={i === 0} onClick={() => setPicked(i - 1)}>
          ‹
        </button>
        <div className="league-week-title" aria-live="polite">
          <b>{leagueWeekLabel(week, leagueNights(weeks))}</b>
          {first && <small className="muted">{dayLabel(first, zone)}</small>}
        </div>
        <button type="button" className="icon-btn league-week-arrow" aria-label="Next week" title="Next week" disabled={i === weeks.length - 1} onClick={() => setPicked(i + 1)}>
          ›
        </button>
      </div>
      {byes.length > 0 && <small className="muted league-week-byes">Bye: {byes.map(s.teamName).join(", ")}</small>}
      {week.games.map((g) => (
        <GameCard key={g.id} s={s} g={g} />
      ))}
    </section>
  );
}

/** A division's bracket on its own page (the app's HostedBracketScreen). */
export const bracketHref = (tournamentId: string, divisionId: string) =>
  `/tournaments/${encodeURIComponent(tournamentId)}/bracket?division=${encodeURIComponent(divisionId)}`;

/** The selected division's bracket: a column per round, each game's card with what the viewer can do. On Results and the bracket's own page. */
export function BracketView({ s }: { s: TournamentState }) {
  const columns = new Map<string, EngineGame[]>();
  for (const g of s.games.filter((x) => isBracketStage(x.stage))) {
    const key = `${g.stage}:${g.round}`;
    columns.set(key, [...(columns.get(key) ?? []), g]);
  }
  return (
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
  );
}

export function ResultsTab({ s }: { s: TournamentState }) {
  const d = s.division;
  if (!d || !s.t) return <NoDivisions s={s} />;
  const league = s.t.kind === "league";
  const places = d.placements.length > 0 ? d.placements : placementsOf(formatOf(s.t, d), d.seeds, s.games);
  const pools = poolTeams(s.games);
  const hasBracket = s.games.some((x) => isBracketStage(x.stage));
  return (
    <div className="stack">
      <DivisionPicker s={s} />
      {s.games.length === 0 && <p className="empty">Results show up here once games are played.</p>}
      {places.length > 0 && (
        <>
          <section className="card hosted-champion">
            <small className="hosted-eyebrow">Champion</small>
            <b>{s.teamName(places[0])}</b>
            <span className="muted">{divisionLabel(d)} champion</span>
          </section>
          <section className="card">
            <h2 className="card-title">Final standings</h2>
            <table className="data-table hosted-standings">
              <tbody>
                {places.map((id, i) => (
                  <tr key={id} className={s.captainOf.has(id) ? "hosted-mine" : undefined}>
                    <td className="narrow hosted-rank">{ordinal(i + 1)}</td>
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
              <table className="data-table hosted-standings">
                <thead>
                  <tr>
                    <th className="narrow">#</th>
                    <th>Team</th>
                    <th className="narrow">W</th>
                    <th className="narrow">L</th>
                    <th className="narrow">+/−</th>
                    <th className="narrow">PF</th>
                  </tr>
                </thead>
                <tbody>
                  {standings(teams, s.games.filter((g) => g.pool === pool)).map((row, i) => (
                    <tr key={row.teamId} className={s.captainOf.has(row.teamId) ? "hosted-mine" : undefined}>
                      <td className="narrow hosted-rank">{i + 1}</td>
                      <td>{s.teamName(row.teamId)}</td>
                      <td className="narrow">{row.wins}</td>
                      <td className="narrow">{row.losses}</td>
                      <td className={`narrow${pointDiff(row) > 0 ? " hosted-plus" : ""}`}>{pointDiff(row) > 0 ? `+${pointDiff(row)}` : pointDiff(row)}</td>
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
      {hasBracket && (
        <section className="card">
          <div className="hosted-card-head">
            <h2 className="card-title">Bracket</h2>
            <Link className="text-btn" href={bracketHref(s.id, d.id)}>
              Open bracket
            </Link>
          </div>
          <BracketView s={s} />
        </section>
      )}
    </div>
  );
}
