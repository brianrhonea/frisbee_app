"use client";
// Entering a team, a step at a time, on a page of its own
// (/tournaments/:id/enter; the app's RespondScreen):
//
//   1. Respond: an invite's Accept or Decline (or, for a public event,
//      Apply), with the team, division and captains.
//   2. Roster: the players the team brings, or "Set later" (by the deadline).
//   3. Payment: pay now (Stripe's checkout inside this page), or later.
//   4. Done: "Request confirmed!" (or "Request sent!" while the host decides),
//      with what's left.
//
// ?team= with an entry already in opens at the step still to do (or at
// ?step=roster|pay). Every rule is the API's (PUT .../entries/:teamId,
// .../roster, .../status); this page only offers what the API takes.
import {
  divisionLabel,
  effectiveDeadline,
  effectiveMinRoster,
  type EntryDoc,
  type EntryStatus,
  entryChecklist,
  feeLabel,
  inviteExpired,
  inviteExpiredMessage,
  type RosterPlayer,
  teamFee,
  type TeamRoster,
} from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";
import type { Doc } from "@/lib/live";
import { LocalTime } from "../LocalTime";
import { PayOnline } from "../payments/Payments";
import { TeamMark } from "./TournamentGames";
import { type MyTeam, type TournamentState, tournamentPath, useAction, useTournament } from "./useTournament";
import "./tournaments.css";
import { useConfirm } from "@/components/ui/ConfirmDialog";

const maxCaptains = 4;

type Mode = "apply" | "invite" | "entered";
type Step = "respond" | "roster" | "pay" | "done" | "declined";
const stepTitles: Record<Exclude<Step, "done" | "declined">, string> = { respond: "Respond", roster: "Roster", pay: "Payment" };

export function EnterTeam({ tournamentId, teamId, step }: { tournamentId: string; teamId?: string; step?: string }) {
  const s = useTournament(tournamentId);
  if (!s.loaded || (s.t && !s.divisions.length && s.t.divisions.length > 0)) return <p className="muted" aria-busy="true">Loading…</p>;
  if (!s.t) return <p className="empty">This event isn&apos;t here: it may have been removed, or it hasn&apos;t been published yet.</p>;
  if (!s.entriesLoaded) return <p className="muted" aria-busy="true">Loading…</p>;
  return <EnterTeamLoaded key={teamId ?? ""} s={s} teamId={teamId} step={step} />;
}

/**
 * The page once the event is in. What it is (an invite, an application or
 * an entered team's next steps) and whether the viewer may do it are
 * settled when it opens: the flow's own writes (accepting, declining,
 * applying) change the entry, and mustn't swap the page out from under it.
 */
function EnterTeamLoaded({ s, teamId, step }: { s: TournamentState; teamId?: string; step?: string }) {
  const [opened] = useState(() => gateOf(s, teamId));
  const { mode, why } = opened;
  const back = `/tournaments/${encodeURIComponent(s.id)}`;
  const entry = teamId ? s.entryOf(teamId) : null;
  const team = teamId ? s.myAdminTeams.find((m) => m.id === teamId) : undefined;
  return (
    <div className="stack hosted-page enter-team">
      <header className="bracket-page-head">
        <small className="muted">
          <Link href={back}>← {s.t!.name}</Link>
        </small>
        <h1>{mode === "invite" ? "Respond to the invite" : mode === "entered" ? "Your entry" : "Enter a team"}</h1>
      </header>
      {why ? <p className="empty">{why}</p> : <EntryFlow s={s} mode={mode} entry={opened.entry} liveEntry={entry} team={team} preselect={teamId} back={back} startAt={step} />}
    </div>
  );
}

/** What the page is for, and why the viewer can't (null when they can), from the state it opened with. */
function gateOf(s: TournamentState, teamId: string | undefined): { mode: Mode; why: string | null; entry: Doc<EntryDoc> | null } {
  const entry = teamId ? s.entryOf(teamId) : null;
  const team = teamId ? s.myAdminTeams.find((m) => m.id === teamId) : undefined;
  const mode: Mode = entry?.status === "invited" ? "invite" : entry && !["withdrawn", "declined"].includes(entry.status) ? "entered" : "apply";
  const t = s.t!;
  const why =
    mode === "apply"
      ? t.status !== "registration"
        ? "Registration isn't open."
        : t.visibility !== "public"
          ? "Teams play here by the host's invitation."
          : s.divisions.length === 0
            ? "The host is still setting up divisions."
            : s.myActiveEntry && s.myActiveEntry.id !== teamId
              ? `${s.myActiveEntry.teamName} is already entered here.`
              : s.teamsToEnter.length === 0
                ? "None of the teams you run can enter: you need to be an owner or admin of a team that hasn't entered."
                : null
      : !team && !(entry && s.uid && entry.captainIds.includes(s.uid))
        ? "Only the team's admins and captains can change its entry."
        : mode === "invite" && entry && inviteExpired(entry, new Date())
          ? inviteExpiredMessage
          : null;
  return { mode, why, entry };
}

/** Where an entered team picks up: ?step=, else the first thing still to do. */
function firstStep(s: TournamentState, entry: Doc<EntryDoc> | null, asked: string | undefined): Step {
  if (asked === "roster" || asked === "pay") return asked;
  // Changing captains (the event page's Captains) is the first step again.
  if (asked === "captains") return "respond";
  if (!entry || entry.status === "invited") return "respond";
  const d = s.divisions.find((x) => x.id === entry.divisionId);
  const mixed = s.t?.entryType === "players" && s.t?.teamEntry === true;
  if (!mixed && (entry.roster?.length ?? 0) < effectiveMinRoster({ minRoster: d?.minRoster ?? null })) return "roster";
  return "pay";
}

function EntryFlow({
  s,
  mode,
  entry,
  liveEntry,
  team: fixedTeam,
  preselect,
  back,
  startAt,
}: {
  s: TournamentState;
  mode: Mode;
  /** The entry as the page opened with it. */
  entry: Doc<EntryDoc> | null;
  /** The entry now (after this flow's own writes). */
  liveEntry: Doc<EntryDoc> | null;
  team: MyTeam | undefined;
  preselect?: string;
  back: string;
  startAt?: string;
}) {
  const t = s.t!;
  const [step, setStep] = useState<Step>(() => (mode === "entered" ? firstStep(s, entry, startAt) : "respond"));
  const [teamId, setTeamId] = useState(preselect ?? s.teamsToEnter[0]?.id ?? "");
  const [answer, setAnswer] = useState<EntryStatus | null>(mode === "entered" && entry ? entry.status : null);
  // The host's own team has no fee (teamFee).
  const fee = teamFee(t, teamId);
  const owes = !!fee && fee.amountCents > 0;
  const deadline = effectiveDeadline(t);
  const steps: Array<Exclude<Step, "done" | "declined">> = owes ? ["respond", "roster", "pay"] : ["respond", "roster"];
  const next = (from: Step) => setStep(from === "respond" ? "roster" : from === "roster" && owes ? "pay" : "done");
  const current = s.entryOf(teamId) ?? liveEntry ?? entry;

  if (step === "declined") {
    return (
      <section className="card respond-done">
        <h2>You declined</h2>
        <p className="muted">The organizers can see your team won&apos;t be playing. If plans change, ask them to invite you again.</p>
        <div className="home-actions">
          <Link className="btn" href={back}>
            Back to the event
          </Link>
        </div>
      </section>
    );
  }
  if (step === "done") {
    return <Done s={s} teamId={teamId} status={answer ?? current?.status ?? "applied"} back={back} owes={owes} deadline={deadline} onStep={setStep} />;
  }
  const index = steps.indexOf(step);
  return (
    <div className="stack">
      <div className="form-steps">
        <b className="form-steps-title">
          Step {index + 1} of {steps.length} · {stepTitles[step]}
        </b>
        <div className="form-steps-bar" aria-hidden="true">
          {steps.map((x, i) => (
            <span key={x} className={i <= index ? "on" : ""} />
          ))}
        </div>
      </div>
      {deadline && step !== "respond" && (
        <p className="muted small">
          Roster and payment are due <LocalTime iso={deadline.toISOString()} />.
        </p>
      )}
      {step === "respond" && (
        <RespondStep
          s={s}
          mode={mode}
          entry={entry}
          fixedTeam={fixedTeam}
          teamId={teamId}
          setTeamId={setTeamId}
          fee={owes && fee ? feeLabel(fee) : null}
          deadline={deadline}
          back={back}
          onAnswered={(status) => {
            setAnswer(status);
            next("respond");
          }}
          onDeclined={() => setStep("declined")}
        />
      )}
      {step === "roster" && current && <RosterStep s={s} entry={current} deadline={deadline} onNext={() => next("roster")} />}
      {step === "pay" && s.user && (
        <section className="card settings-form">
          <h2 className="card-title">Entry fee{fee ? ` · ${feeLabel(fee)}` : ""}</h2>
          <p className="muted small">
            Pay now, or come back and pay {deadline ? <>by <LocalTime iso={deadline.toISOString()} /></> : "later"}.
          </p>
          {fee?.instructions && <p className="small">{fee.instructions}</p>}
          <PayOnline user={s.user} tournamentId={s.id} teamId={teamId} withStatus />
          <div className="home-actions">
            <button type="button" className="btn btn-primary" onClick={() => next("pay")}>
              Continue
            </button>
            <button type="button" className="btn btn-quiet" onClick={() => next("pay")}>
              Pay later{deadline ? " (before the deadline)" : ""}
            </button>
          </div>
        </section>
      )}
    </div>
  );
}

function RespondStep({
  s,
  mode,
  entry,
  fixedTeam,
  teamId,
  setTeamId,
  fee,
  deadline,
  back,
  onAnswered,
  onDeclined,
}: {
  s: TournamentState;
  mode: Mode;
  entry: Doc<EntryDoc> | null;
  fixedTeam: MyTeam | undefined;
  teamId: string;
  setTeamId: (id: string) => void;
  fee: string | null;
  deadline: Date | null;
  back: string;
  onAnswered: (status: EntryStatus) => void;
  onDeclined: () => void;
}) {
  const askConfirm = useConfirm();
  const t = s.t!;
  const choices = fixedTeam ? [fixedTeam] : s.teamsToEnter;
  const team = choices.find((m) => m.id === teamId);
  // The division matching the team's own, if there is one.
  const matching = (m: MyTeam | undefined) => s.divisions.find((d) => m && d.division === m.division && d.level === m.level)?.id ?? s.divisions[0]?.id ?? "";
  const [div, setDiv] = useState(entry?.divisionId ?? matching(team));
  const [captains, setCaptains] = useState<string[]>(entry && mode === "entered" ? entry.captainIds : s.uid ? [s.uid] : []);
  const { busy, error, run } = useAction();
  const names = Object.entries(team?.memberNames ?? {}).sort((a, b) => a[1].localeCompare(b[1]));
  const entryPath = team ? `${tournamentPath(s.id)}/entries/${encodeURIComponent(team.id)}` : "";

  async function accept() {
    if (!team) return;
    const r = await run<{ status: EntryStatus }>(entryPath, "PUT", { divisionId: div, captainIds: captains });
    if (r.ok) onAnswered(r.value?.status ?? (mode === "invite" ? "accepted" : "applied"));
  }
  async function decline() {
    if (!team || !(await askConfirm({ message: `Decline the invite to ${t.name}? The organizers will see your team isn't playing.`, confirmLabel: "Decline", destructive: true }))) return;
    const r = await run(`${entryPath}/status`, "PUT", { status: "withdrawn", reason: "declined" });
    if (r.ok) onDeclined();
  }

  return (
    <form
      className="stack"
      onSubmit={(e) => {
        e.preventDefault();
        void accept();
      }}
    >
      <section className="card settings-form respond-summary">
        <h2 className="card-title">{t.name}</h2>
        <dl className="form-review">
          <div className="form-review-row">
            <dt>When</dt>
            <dd>
              <LocalTime iso={t.startsOn} />
            </dd>
          </div>
          {t.location && (
            <div className="form-review-row">
              <dt>Where</dt>
              <dd>{t.location}</dd>
            </div>
          )}
          <div className="form-review-row">
            <dt>Host</dt>
            <dd>{t.hostName}</dd>
          </div>
          {t.director?.name && (
            <div className="form-review-row">
              <dt>Director</dt>
              <dd>{t.director.name}</dd>
            </div>
          )}
          <div className="form-review-row">
            <dt>Entry fee</dt>
            <dd>{fee ?? "Free"}</dd>
          </div>
          {deadline && (
            <div className="form-review-row">
              <dt>Roster and fee due</dt>
              <dd>
                <LocalTime iso={deadline.toISOString()} />
              </dd>
            </div>
          )}
          {mode === "invite" && entry?.replyBy && (
            <div className="form-review-row">
              <dt>Reply by</dt>
              <dd>
                <LocalTime iso={entry.replyBy} />
              </dd>
            </div>
          )}
        </dl>
      </section>
      <section className="card settings-form">
        <h2 className="card-title">Team</h2>
        {fixedTeam ? (
          <div className="enter-team-option on">
            <TeamMark name={fixedTeam.name ?? ""} />
            <b>{fixedTeam.name}</b>
          </div>
        ) : (
          <div className="stack" role="radiogroup" aria-label="Team">
            {choices.map((m) => (
              <label key={m.id} className={`enter-team-option${m.id === teamId ? " on" : ""}`}>
                <input
                  type="radio"
                  name="team"
                  checked={m.id === teamId}
                  onChange={() => {
                    setTeamId(m.id);
                    setDiv(matching(m));
                    setCaptains(s.uid ? [s.uid] : []);
                  }}
                />
                <TeamMark name={m.name ?? ""} />
                <span>
                  <b>{m.name}</b>
                  <small className="muted">
                    {Object.keys(m.memberNames ?? {}).length} {Object.keys(m.memberNames ?? {}).length === 1 ? "member" : "members"}
                  </small>
                </span>
              </label>
            ))}
          </div>
        )}
      </section>
      {mode === "apply" && (
        <section className="card settings-form">
          <h2 className="card-title">Division</h2>
          <div className="segmented hosted-divisions" role="group" aria-label="Division">
            {s.divisions.map((d) => {
              const full = s.entriesIn(d.id, "accepted").length >= d.maxTeams;
              return (
                <button key={d.id} type="button" className={d.id === div ? "on" : ""} aria-pressed={d.id === div} onClick={() => setDiv(d.id)}>
                  {divisionLabel(d)}
                  {full ? " · full: waitlist" : ""}
                </button>
              );
            })}
          </div>
        </section>
      )}
      <section className="card settings-form">
        <h2 className="card-title">Captains</h2>
        <p className="muted small">Captains report and confirm scores (up to {maxCaptains}).</p>
        {names.length === 0 ? (
          <p className="muted small">The team&apos;s members show up here to pick captains.</p>
        ) : (
          <fieldset className="hosted-captains">
            <legend className="sr-only">Captains</legend>
            {names.map(([uid, name]) => (
              <label key={uid} className="switch-row">
                <input
                  type="checkbox"
                  checked={captains.includes(uid)}
                  disabled={!captains.includes(uid) && captains.length >= maxCaptains}
                  onChange={(e) => setCaptains(e.target.checked ? [...captains, uid].slice(0, maxCaptains) : captains.filter((x) => x !== uid))}
                />
                {name}
                {uid === s.uid ? " (you)" : ""}
              </label>
            ))}
          </fieldset>
        )}
      </section>
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions">
        <button className="btn btn-primary" disabled={busy || !team || !div || captains.length === 0}>
          {mode === "invite" ? "Accept" : mode === "entered" ? "Save and continue" : "Apply"}
        </button>
        {mode === "invite" ? (
          <button type="button" className="btn" disabled={busy || !team} onClick={() => void decline()}>
            Decline
          </button>
        ) : (
          <Link className="btn btn-quiet" href={back}>
            Cancel
          </Link>
        )}
      </div>
    </form>
  );
}

function RosterStep({ s, entry, deadline, onNext }: { s: TournamentState; entry: Doc<EntryDoc>; deadline: Date | null; onNext: () => void }) {
  const [players, setPlayers] = useState<RosterPlayer[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [picked, setPicked] = useState<string[]>(entry.roster ?? []);
  const { busy, error, run } = useAction();
  const d = s.divisions.find((x) => x.id === entry.divisionId);
  const mixed = s.t?.entryType === "players" && s.t?.teamEntry === true;
  const minimum = mixed ? 0 : effectiveMinRoster({ minRoster: d?.minRoster ?? null });
  const locked = s.t ? ["live", "finished"].includes(s.t.status) : false;

  useEffect(() => {
    if (!s.user) return;
    callApi<TeamRoster>(s.user, `/v1/teams/${encodeURIComponent(entry.id)}/roster`).then(
      (r) => {
        setPlayers([...r.players].sort((a, b) => a.name.localeCompare(b.name)));
        // A first roster starts with everyone ticked.
        if (!entry.roster?.length) setPicked(r.players.map((p) => p.id).slice(0, 60));
      },
      (e) => setLoadError(problem(e, "Couldn't load the team's roster. Try again.")),
    );
  }, [s.user, entry.id, entry.roster?.length]);

  async function save() {
    const r = await run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(entry.id)}/roster`, "PUT", { playerIds: picked });
    if (r.ok) onNext();
  }

  return (
    <section className="card settings-form">
      <h2 className="card-title">Who&apos;s playing for {entry.teamName}?</h2>
      <p className="muted small">
        {minimum > 0 ? `Pick at least ${minimum} players from your roster. ` : ""}
        {picked.length} picked. You can change it until play starts.
      </p>
      {loadError && <p className="form-error">{loadError}</p>}
      {!players && !loadError && <p className="muted" aria-busy="true">Loading the roster…</p>}
      {players && players.length === 0 && (
        <p className="muted small">
          Your roster is empty. <Link href={`/teams/${encodeURIComponent(entry.id)}/roster`}>Add players to the team</Link>, then come back.
        </p>
      )}
      {players && players.length > 0 && (
        <fieldset className="hosted-captains roster-pick" disabled={locked}>
          <legend className="sr-only">Players</legend>
          <label className="switch-row">
            <input
              type="checkbox"
              checked={picked.length === players.length}
              onChange={(e) => setPicked(e.target.checked ? players.map((p) => p.id).slice(0, 60) : [])}
            />
            <b>Everyone</b>
          </label>
          {players.map((p) => (
            <label key={p.id} className="switch-row">
              <input type="checkbox" checked={picked.includes(p.id)} onChange={(e) => setPicked(e.target.checked ? [...picked, p.id] : picked.filter((x) => x !== p.id))} />
              {p.number != null ? `#${p.number} ` : ""}
              {p.name}
            </label>
          ))}
        </fieldset>
      )}
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions">
        <button type="button" className="btn btn-primary" disabled={busy || locked || picked.length < Math.max(minimum, 1)} onClick={() => void save()}>
          Save roster
        </button>
        <button type="button" className="btn btn-quiet" onClick={onNext}>
          Set later{deadline ? " (before the deadline)" : ""}
        </button>
      </div>
    </section>
  );
}

function Done({
  s,
  teamId,
  status,
  back,
  owes,
  deadline,
  onStep,
}: {
  s: TournamentState;
  teamId: string;
  status: EntryStatus;
  back: string;
  owes: boolean;
  deadline: Date | null;
  onStep: (step: Step) => void;
}) {
  const entry = s.entryOf(teamId);
  const d = s.divisions.find((x) => x.id === entry?.divisionId);
  const mixed = s.t?.entryType === "players" && s.t?.teamEntry === true;
  const [paid, setPaid] = useState<boolean | null>(owes ? null : true);
  useEffect(() => {
    if (!owes || !s.user) return;
    callApi<{ paid: boolean }>(s.user, `${tournamentPath(s.id)}/pay?team=${encodeURIComponent(teamId)}`).then(
      (o) => setPaid(o.paid),
      () => setPaid(false),
    );
  }, [owes, s.user, s.id, teamId]);
  const list = entryChecklist({
    status,
    rosterSize: mixed ? null : (entry?.roster?.length ?? 0),
    minRoster: effectiveMinRoster({ minRoster: d?.minRoster ?? null }),
    paid: paid === true,
    owes,
    deadline,
    now: Date.now(),
  });
  const title = status === "accepted" ? "Request confirmed!" : status === "waitlisted" ? "You're on the waitlist" : "Request sent!";
  const lead =
    status === "accepted"
      ? `${entry?.teamName ?? "Your team"} is in ${s.t?.name}.`
      : status === "waitlisted"
        ? "The division is full. You'll move up if a spot opens."
        : "The organizers will accept your team or put it on the waitlist. You'll get a notification.";
  return (
    <section className="card respond-done" aria-live="polite">
      <div className="respond-done-mark" aria-hidden="true">
        ✓
      </div>
      <h2>{title}</h2>
      <p>{lead}</p>
      <ul className="respond-checklist">
        <li className={status === "accepted" ? "done" : ""}>{status === "accepted" ? "Accepted" : status === "waitlisted" ? "On the waitlist" : "Waiting for the organizers"}</li>
        {!mixed && (
          <li className={list.rosterSet ? "done" : ""}>
            {list.rosterSet ? "Roster set" : "Roster to set"}
            {/* It can change until play starts. */}
            {s.t?.status !== "live" && s.t?.status !== "finished" && (
              <button type="button" className="text-btn" onClick={() => onStep("roster")}>
                {list.rosterSet ? "Change" : "Set roster"}
              </button>
            )}
          </li>
        )}
        {owes && (
          <li className={list.paid ? "done" : ""}>
            {paid === null ? "Checking payment…" : list.paid ? "Paid" : "Fee to pay"}
          </li>
        )}
      </ul>
      {/* Pay straight away (PayOnlineButton on the app's Done screen); it says why when it can't yet. */}
      {owes && paid === false && s.user && <PayOnline user={s.user} tournamentId={s.id} teamId={teamId} />}
      {!list.complete && deadline && (
        <p className="muted small">
          Due <LocalTime iso={deadline.toISOString()} />. You can finish from your team&apos;s page.
        </p>
      )}
      <div className="home-actions">
        <Link className="btn btn-primary" href={back}>
          Go to the event
        </Link>
        <Link className="btn" href={`/teams/${encodeURIComponent(teamId)}`}>
          Back to the team
        </Link>
      </div>
    </section>
  );
}
