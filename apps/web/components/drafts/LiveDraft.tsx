"use client";
import "./drafts.css";
import {
  type DraftControlAction,
  draftLimits,
  draftSecondsLeft,
  draftTeamOf,
  type GenderMatch,
  genderMatches,
  genderMatchLabels,
  type LiveDraftDoc,
  onTheClock,
  teamsCreated,
} from "@stall10/shared";
import type { User } from "firebase/auth";
import Link from "next/link";
import { useEffect, useState } from "react";
import { useAuth } from "../AuthProvider";
import { attempt, divisionLabel, draftApi, draftHrefs, teamsOf, useDraftDetails, useLiveDraft, useSignups, useTournamentBase } from "./data";

const pickTimes: Array<[number, string]> = [
  [0, "No limit"],
  [30, "30 seconds"],
  [60, "1 minute"],
  [90, "90 seconds"],
  [180, "3 minutes"],
];

/** A second-by-second clock while [on]. */
function useNow(on: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!on) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [on]);
  return now;
}

const describe = (skill: number, gender: GenderMatch | null | undefined) => `Skill ${skill}${gender ? ` · ${genderMatchLabels[gender]}` : ""}`;

/**
 * The captains' draft for one division (the app's LiveDraftScreen): the
 * host chooses captains and starts it, then the captains take turns
 * picking in snake order while the division watches. Every board change
 * comes from the Firestore listener; picks and the host's controls go
 * through the API, which checks whose turn it is.
 */
export function LiveDraft({ tournamentId, divisionId }: { tournamentId: string; divisionId: string }) {
  const { user } = useAuth();
  const uid = user?.uid ?? null;
  const { tournament, divisions, manager, managerKnown } = useTournamentBase(tournamentId, uid);
  const draft = useLiveDraft(tournamentId, divisionId);
  if (!user) return null;
  const division = divisions.data?.find((d) => d.id === divisionId);
  if (!managerKnown || tournament.data === undefined || divisions.data === undefined || (draft.data === undefined && !draft.error)) {
    return <p className="muted" aria-busy="true">Loading…</p>;
  }
  if (!tournament.data || !division) return <div className="empty">Division not found. It may have been removed.</div>;
  const locked = teamsCreated(teamsOf(division));
  return (
    <div className="drafts">
      <h2 className="draft-title">Draft · {divisionLabel(division)}</h2>
      {draft.data ? (
        <Board user={user} tournamentId={tournamentId} divisionId={divisionId} draft={draft.data} manager={manager} locked={locked} />
      ) : draft.error && !manager ? (
        <div className="empty">Only the host and the division's accepted players can watch this draft.</div>
      ) : manager ? (
        <Setup user={user} tournamentId={tournamentId} divisionId={divisionId} locked={locked} />
      ) : (
        <div className="empty">
          <b>The draft hasn&apos;t started</b>
          <p className="muted">You can watch it here once the host starts it.</p>
        </div>
      )}
    </div>
  );
}

// ---- Before it starts ---------------------------------------------------------------

function Setup({ user, tournamentId, divisionId, locked }: { user: User; tournamentId: string; divisionId: string; locked: boolean }) {
  const signups = useSignups(tournamentId, true).data ?? [];
  const [chosen, setChosen] = useState<string[]>([]);
  const [pickSeconds, setPickSeconds] = useState(90);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const players = signups.filter((s) => s.divisionId === divisionId && s.status === "accepted").sort((a, b) => a.name.localeCompare(b.name));

  // LiveDraftViewModel.startProblem.
  const problem =
    chosen.length < draftLimits.minCaptains
      ? `Choose at least ${draftLimits.minCaptains} captains.`
      : players.length - chosen.length < chosen.length
        ? "There are not enough players for every captain to pick."
        : locked
          ? "The teams have already been created."
          : null;

  function toggle(id: string) {
    setChosen((c) => (c.includes(id) ? c.filter((x) => x !== id) : c.length < draftLimits.maxCaptains ? [...c, id] : c));
  }

  async function start() {
    if (await attempt(setBusy, setError, () => draftApi.start(user, tournamentId, divisionId, chosen, pickSeconds))) setChosen([]);
  }

  return (
    <section className="card">
      <h3 className="card-title">Choose the captains</h3>
      <p className="muted">Each captain owns a team and picks players in turn, snaking back on every round. The order is drawn at random.</p>
      {players.length < 4 ? (
        <p>Accept at least four players first.</p>
      ) : (
        <div className="draft-captain-grid">
          {players.map((p) => (
            <label key={p.id} className="check-row">
              <input type="checkbox" checked={chosen.includes(p.id)} onChange={() => toggle(p.id)} />
              <span>
                {p.name} <span className="muted small">{describe(p.skill, p.gender)}</span>
              </span>
            </label>
          ))}
        </div>
      )}
      <div className="settings-form draft-setup-form">
        <label>
          Time per pick
          <select value={pickSeconds} onChange={(e) => setPickSeconds(Number(e.target.value))}>
            {pickTimes.map(([s, label]) => (
              <option key={s} value={s}>
                {label}
              </option>
            ))}
          </select>
          <small className="muted">The clock is a guide: when time is up, you can auto-pick for the captain.</small>
        </label>
      </div>
      {problem && chosen.length > 0 && <p className="form-error">{problem}</p>}
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions">
        <button type="button" className="btn btn-primary btn-small" disabled={!!problem || busy} onClick={start}>
          Start the draft ({chosen.length} captains)
        </button>
      </div>
    </section>
  );
}

// ---- The board ---------------------------------------------------------------------

function Board(props: { user: User; tournamentId: string; divisionId: string; draft: LiveDraftDoc; manager: boolean; locked: boolean }) {
  const { user, tournamentId, divisionId, draft, manager, locked } = props;
  const isCaptain = draft.captains.some((c) => c.uid === user.uid);
  const details = useDraftDetails(tournamentId, divisionId, manager || isCaptain).data?.players ?? null;
  const running = draft.status === "live";
  const now = useNow(running && draft.pickSeconds > 0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [bySkill, setBySkill] = useState(false);
  const [gender, setGender] = useState<GenderMatch | null>(null);

  const poolSize = Object.keys(draft.pool).length;
  const clock = onTheClock(draft.captainIds, draft.picks, poolSize);
  const nameOf = (uid: string) => draft.pool[uid] ?? draft.captains.find((c) => c.uid === uid)?.name ?? "Player";
  const myTurn = running && clock === user.uid && isCaptain;
  const canPick = running && (myTurn || manager);
  const left = draftSecondsLeft(draft, now);
  const timeUp = left === 0;
  const picked = new Set(draft.picks.map((p) => p.uid));
  const sorting = bySkill && details !== null;
  const pool = Object.entries(draft.pool)
    .filter(([uid]) => !picked.has(uid))
    .filter(([uid]) => gender === null || details?.[uid]?.gender === gender)
    .sort(([a, an], [b, bn]) => (sorting ? (details![b]?.skill ?? 0) - (details![a]?.skill ?? 0) : 0) || an.toLowerCase().localeCompare(bn.toLowerCase()));
  const remaining = poolSize - draft.picks.length;

  const act = (fn: () => Promise<unknown>) => attempt(setBusy, setError, fn);
  const control = (a: DraftControlAction) => act(() => draftApi.control(user, tournamentId, divisionId, a));

  function cancel() {
    if (window.confirm("Cancel the draft? Every pick is thrown away. You can then choose captains and start again.")) control("cancel");
  }
  function finish() {
    const message = remaining === 0
      ? "This saves each captain's picks as the division's teams."
      : `${remaining} players have not been picked and will be left off the teams. You can still add them on the teams screen.`;
    if (window.confirm(`Finish the draft? ${message}`)) act(() => draftApi.finish(user, tournamentId, divisionId));
  }

  const clockText = running && left !== null ? `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}` : null;
  const banner: [string, string | null, string] =
    draft.status === "finished"
      ? ["The draft is finished", "The captains' teams are saved.", "finished"]
      : draft.status === "done"
        ? ["Every player has been picked", manager ? "Finish the draft to make the teams." : null, "done"]
        : draft.status === "paused"
          ? ["The draft is paused", null, "paused"]
          : [
              myTurn ? "You're on the clock" : `${clock ? nameOf(clock) : "Nobody"} is picking`,
              left === null ? null : timeUp ? "Time's up" : `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")} left`,
              myTurn ? "mine" : "live",
            ];

  return (
    <>
      <div className={`draft-banner draft-banner-${banner[2]}`} role="status" aria-live="polite">
        <div>
          <b>{banner[0]}</b>
          {banner[1] && <span>{banner[1]}</span>}
        </div>
        {clockText && (
          <span className="draft-clock" aria-hidden>
            {clockText}
          </span>
        )}
      </div>

      {manager && draft.status !== "finished" && (
        <div className="home-actions draft-controls">
          {draft.status === "live" && (
            <button type="button" className="btn btn-small" disabled={busy} onClick={() => control("pause")}>
              Pause
            </button>
          )}
          {draft.status === "paused" && (
            <button type="button" className="btn btn-small" disabled={busy} onClick={() => control("resume")}>
              Resume
            </button>
          )}
          {draft.picks.length > 0 && (
            <button type="button" className="btn btn-small" disabled={busy} onClick={() => control("undo")}>
              Undo pick
            </button>
          )}
          {draft.status === "live" && (
            <button type="button" className={`btn btn-small${timeUp ? " draft-btn-due" : ""}`} disabled={busy} onClick={() => control("autopick")}>
              Auto-pick
            </button>
          )}
          {!locked && (
            <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={finish}>
              Finish
            </button>
          )}
          <button type="button" className="text-btn" disabled={busy} onClick={cancel}>
            Cancel draft
          </button>
        </div>
      )}
      {draft.status === "finished" && manager && (
        <p>
          <Link className="btn btn-primary btn-small" href={draftHrefs.teamDraft(tournamentId, divisionId)}>
            Open the teams
          </Link>
        </p>
      )}
      {error && <p className="form-error">{error}</p>}

      <h3 className="draft-subtitle">{draft.status === "finished" ? "Teams" : `Teams (${draft.picks.length} of ${poolSize} picked)`}</h3>
      <div className="draft-board">
        {draft.captains.map((c) => (
          <section key={c.uid} className={`card draft-team${c.uid === clock && running ? ` on-clock${myTurn ? " mine" : ""}` : ""}`}>
            <div className="draft-team-head">
              <h4 className="card-title">Team {c.name}</h4>
              <span className="draft-count">{draftTeamOf(draft.picks, c.uid).length}</span>
            </div>
            <ol className="draft-picks">
              {draftTeamOf(draft.picks, c.uid).map((id, i) => (
                <li key={id}>
                  <span>
                    {nameOf(id)}
                    {i === 0 && (
                      <abbr className="draft-cap" title="Captain">
                        C
                      </abbr>
                    )}
                  </span>
                  {details?.[id] && <span className="draft-skill">{details[id].skill ?? 3}</span>}
                </li>
              ))}
            </ol>
          </section>
        ))}
      </div>

      {draft.status !== "finished" && (
        <section className="card">
          <div className="draft-head">
            <h3 className="card-title">Players left ({remaining})</h3>
            {details && (
              <div className="home-actions draft-filters">
                <label className="check-row small">
                  <input type="checkbox" checked={bySkill} onChange={(e) => setBySkill(e.target.checked)} />
                  Best first
                </label>
                {draft.mixed && (
                  <div className="segmented" role="group" aria-label="Gender match">
                    <button type="button" className={gender === null ? "on" : ""} onClick={() => setGender(null)}>
                      All
                    </button>
                    {genderMatches.map((g) => (
                      <button key={g} type="button" className={gender === g ? "on" : ""} onClick={() => setGender(g)}>
                        {genderMatchLabels[g]}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>
          {pool.length === 0 ? (
            <p className="muted">Nobody is left.</p>
          ) : (
            <ul className="draft-pool">
              {pool.map(([uid, name]) => (
                <li key={uid}>
                  <span>
                    {name}
                    {details?.[uid] && <span className="muted small"> {describe(details[uid].skill ?? 3, details[uid].gender)}</span>}
                  </span>
                  {canPick && (
                    <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={() => act(() => draftApi.pick(user, tournamentId, divisionId, uid))}>
                      Draft
                    </button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </>
  );
}
