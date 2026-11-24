"use client";
import "./drafts.css";
import {
  type GenderMatch,
  genderMatches,
  genderMatchLabels,
  type PlayerSignupDoc,
  type SignupStatus,
  signupLimits,
  signupStatusLabels,
  skillHints,
  effectiveDeadline,
} from "@stall10/shared";
import type { User } from "firebase/auth";
import Link from "next/link";
import { type FormEvent, useState } from "react";
import type { Doc } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { HostPaymentControls, PayOnline } from "../payments/Payments";
import {
  attempt,
  dateLabel,
  type DivisionDoc,
  divisionLabel,
  draftApi,
  draftHrefs,
  feeLabel,
  isScheduled,
  type TournamentDoc,
  teamsOf,
  useHasGames,
  useLiveDraft,
  useMyPayment,
  useMySignup,
  usePayments,
  useSignups,
  useTournamentBase,
} from "./data";

type Fee = NonNullable<TournamentDoc["bidFee"]>;

/** How to pay: the host's instructions, as paying on Stall 10 isn't here yet. */
const howToPay = (fee: Fee) => fee.instructions?.trim() || "Paying on Stall 10 is coming soon: the host will tell you how to pay.";

const overdue = (fee: Fee | null | undefined, paid: boolean) =>
  !!fee && fee.amountCents > 0 && !!fee.dueAt && Date.now() > Date.parse(fee.dueAt) && !paid;

/**
 * The Players section of a player-entry tournament or league (the app's
 * PlayersTab): a player's own signup, and for the host's organizers every
 * signup (accept, waitlist, decline, mark paid), the drafted teams and the
 * way to draft them. Everyone else sees the teams once the schedule is out.
 */
export function PlayerSignups({ tournamentId, divisionId: initial }: { tournamentId: string; divisionId?: string }) {
  const { user } = useAuth();
  const uid = user?.uid ?? null;
  const { tournament, divisions, manager } = useTournamentBase(tournamentId, uid);
  const [picked, setPicked] = useState<string | null>(initial ?? null);
  if (!user) return null;
  if (tournament.error || divisions.error) return <p className="form-error">{tournament.error ?? divisions.error}</p>;
  if (tournament.data === undefined || divisions.data === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
  const t = tournament.data;
  if (!t) return <p className="muted">This event doesn&apos;t exist, or you can&apos;t see it.</p>;
  if (t.entryType !== "players") return <p className="muted">Teams enter this event, not individual players.</p>;
  const list = divisions.data;
  const d = list.find((x) => x.id === picked) ?? list[0] ?? null;

  return (
    <div className="drafts">
      {list.length > 1 && (
        <div className="segmented" role="tablist" aria-label="Division">
          {list.map((x) => (
            <button key={x.id} type="button" role="tab" aria-selected={x.id === d?.id} className={x.id === d?.id ? "on" : ""} onClick={() => setPicked(x.id)}>
              {divisionLabel(x)}
            </button>
          ))}
        </div>
      )}
      {list.length === 0 && (
        <p className="muted">{manager ? "Add a division so players can sign up." : "The host is still setting up divisions."}</p>
      )}
      <MySignup user={user} tournamentId={tournamentId} tournament={t} divisions={list} />
      {d && (manager || isScheduled(t)) && <DraftedTeams user={user} tournamentId={tournamentId} tournament={t} division={d} manager={manager} />}
      {d && manager && <SignupList user={user} tournamentId={tournamentId} tournament={t} division={d} />}
    </div>
  );
}

// ---- The player's own signup (PlayerSignupCard) ---------------------------------------

function MySignup({ user, tournamentId, tournament: t, divisions }: { user: User; tournamentId: string; tournament: TournamentDoc; divisions: Doc<DivisionDoc>[] }) {
  const mine = useMySignup(tournamentId, user.uid).data;
  const payment = useMyPayment(tournamentId, user.uid).data;
  const accepted = mine?.status === "accepted" ? mine.divisionId : null;
  const draft = useLiveDraft(tournamentId, accepted).data;
  const [editing, setEditing] = useState(false);
  // A new signup's next steps (the app's signup flow): Pay (with a fee), then Done.
  const [phase, setPhase] = useState<"pay" | "done" | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const fee = t.bidFee ?? null;
  const isIn = !!mine && mine.status !== "withdrawn";
  const open = t.status === "registration" && t.visibility === "public" && divisions.length > 0;

  if (mine === undefined) return null;
  if (!isIn && !open) {
    const note =
      t.status === "draft" ? null : t.visibility === "inviteOnly" ? "Invite only. Follow along for the schedule and results." : t.status !== "registration" ? "Signups are closed." : null;
    return note ? <p className="muted">{note}</p> : null;
  }

  async function withdraw() {
    const message = t.status === "registration" ? "You can sign up again while registration is open." : "Registration has closed, so you may not be able to sign up again.";
    if (!window.confirm(`Withdraw from ${t.name ?? "this event"}? ${message}`)) return;
    await attempt(setBusy, setError, () => draftApi.setStatus(user, tournamentId, user.uid, "withdrawn"));
  }

  if (editing) {
    return (
      <section className="card">
        <h2 className="card-title">{isIn ? "Your signup" : "Sign up"}</h2>
        <SignupForm
          divisions={divisions}
          initial={isIn ? mine : null}
          fee={fee}
          busy={busy}
          error={error}
          onCancel={() => {
            setEditing(false);
            setError(null);
          }}
          onSave={async (a) => {
            const first = !isIn;
            if (await attempt(setBusy, setError, () => draftApi.saveMySignup(user, tournamentId, a))) {
              setEditing(false);
              if (first) setPhase(fee && fee.amountCents > 0 ? "pay" : "done");
            }
          }}
        />
      </section>
    );
  }

  if (!isIn) {
    return (
      <section className="card">
        <h2 className="card-title">Play in {t.name}</h2>
        <p>
          {fee && `${feeLabel(fee)} entry fee. `}
          {t.draftMode === "captains"
            ? "Sign up on your own; captains chosen by the host draft the teams."
            : "Sign up on your own; the host builds balanced teams from everyone who signs up."}
        </p>
        <div className="home-actions">
          <button type="button" className="btn btn-primary btn-small" onClick={() => setEditing(true)}>
            {fee ? `Sign up · ${feeLabel(fee)}` : "Sign up"}
          </button>
        </div>
      </section>
    );
  }

  const division = divisions.find((x) => x.id === mine.divisionId);
  const paid = payment?.paid === true;
  const deadline = effectiveDeadline(t);
  if (phase === "pay" && fee && !paid) {
    return (
      <section className="card settings-form">
        <small className="muted">Step 2 of 2 · Payment</small>
        <h2 className="card-title">Entry fee · {feeLabel(fee)}</h2>
        <p className="muted small">Pay now, or come back and pay{deadline ? ` by ${dateLabel(deadline.toISOString())}` : " later"}.</p>
        {fee.instructions && <p className="small">{fee.instructions}</p>}
        <PayOnline user={user} tournamentId={tournamentId} />
        <div className="home-actions">
          <button type="button" className="btn btn-quiet btn-small" onClick={() => setPhase("done")}>
            Pay later
          </button>
        </div>
      </section>
    );
  }
  if (phase === "pay" || phase === "done") {
    const owes = !!fee && fee.amountCents > 0;
    return (
      <section className="card respond-done" aria-live="polite">
        <div className="respond-done-mark" aria-hidden="true">
          ✓
        </div>
        <h2>You&apos;re signed up!</h2>
        <p>{mine.status === "accepted" ? `You're in ${t.name}.` : mine.status === "waitlisted" ? "The division is full: you're on the waitlist." : "The host will confirm your spot."}</p>
        <ul className="respond-checklist">
          <li className="done">Signed up</li>
          {owes && (
            <li className={paid ? "done" : ""}>
              {paid ? "Paid" : "Fee to pay"}
              {!paid && (
                <button type="button" className="text-btn" onClick={() => setPhase("pay")}>
                  Pay now
                </button>
              )}
            </li>
          )}
        </ul>
        {owes && !paid && deadline && <p className="muted small">Due {dateLabel(deadline.toISOString())}.</p>}
        <div className="home-actions">
          <button type="button" className="btn btn-primary btn-small" onClick={() => setPhase(null)}>
            Done
          </button>
        </div>
      </section>
    );
  }
  return (
    <section className="card">
      <h2 className="card-title">
        Your signup <StatusPill status={mine.status} />
      </h2>
      <p className="muted">
        {[division && divisionLabel(division), `Skill ${mine.skill}`, mine.gender && genderMatchLabels[mine.gender]].filter(Boolean).join(" · ")}
      </p>
      {draft && draft.status !== "finished" && (
        <p>
          <Link className="btn btn-small" href={draftHrefs.liveDraft(tournamentId, mine.divisionId)}>
            {draft.captains.some((c) => c.uid === user.uid) ? "The draft is live: you're a captain" : "The draft is live: watch it"}
          </Link>
        </p>
      )}
      {fee && (mine.status === "accepted" || mine.status === "applied") && (
        <p className="small">
          {paid
            ? "Entry fee paid."
            : overdue(fee, paid)
              ? `Entry fee overdue: ${feeLabel(fee)}. ${howToPay(fee)}`
              : `Entry fee ${feeLabel(fee)} to pay. ${howToPay(fee)}${fee.dueAt ? ` Due ${dateLabel(fee.dueAt)}.` : ""}`}
        </p>
      )}
      {fee && !paid && (mine.status === "accepted" || mine.status === "applied") && <PayOnline user={user} tournamentId={tournamentId} />}
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions">
        {t.status === "registration" && mine.status !== "accepted" && (
          <button type="button" className="text-btn" onClick={() => setEditing(true)} disabled={busy}>
            Edit
          </button>
        )}
        <button type="button" className="text-btn" onClick={withdraw} disabled={busy}>
          Withdraw
        </button>
      </div>
    </section>
  );
}

/** A thin bar split by gender match (GenderSplitBar in the app). */
export function GenderSplit({ mmp, wmp, unknown }: { mmp: number; wmp: number; unknown: number }) {
  const total = mmp + wmp + unknown;
  if (!total) return null;
  return (
    <div className="draft-split" role="img" aria-label={`${mmp} MMP, ${wmp} WMP${unknown > 0 ? `, ${unknown} not set` : ""}`}>
      {mmp > 0 && <i className="draft-dot-mmp" style={{ flexGrow: mmp }} />}
      {wmp > 0 && <i className="draft-dot-wmp" style={{ flexGrow: wmp }} />}
      {unknown > 0 && <i className="draft-dot-unset" style={{ flexGrow: unknown }} />}
    </div>
  );
}

function StatusPill({ status }: { status: SignupStatus }) {
  return <span className={`pill pill-soft draft-status draft-status-${status}`}>{signupStatusLabels[status]}</span>;
}

/** Division, skill and gender match (the app's signup dialog). */
function SignupForm(props: {
  divisions: Doc<DivisionDoc>[];
  initial: PlayerSignupDoc | null;
  fee: Fee | null;
  busy: boolean;
  error: string | null;
  onCancel: () => void;
  onSave: (a: { divisionId: string; skill: number; gender: GenderMatch | null }) => void;
}) {
  const { divisions, initial, fee } = props;
  const [divisionId, setDivisionId] = useState(divisions.some((d) => d.id === initial?.divisionId) ? initial!.divisionId : divisions[0].id);
  const [skill, setSkill] = useState(initial?.skill ?? 3);
  const [gender, setGender] = useState<GenderMatch | null>(initial?.gender ?? null);
  const mixed = divisions.find((d) => d.id === divisionId)?.division === "mixed";

  function submit(e: FormEvent) {
    e.preventDefault();
    props.onSave({ divisionId, skill, gender: mixed ? gender : null });
  }

  return (
    <form className="settings-form" onSubmit={submit}>
      {fee && (
        <p className="muted">
          Entry fee: {feeLabel(fee)}. {howToPay(fee)} {fee.dueAt && `Due ${dateLabel(fee.dueAt)}.`}
        </p>
      )}
      {divisions.length > 1 && (
        <label>
          Division
          <select value={divisionId} onChange={(e) => setDivisionId(e.target.value)}>
            {divisions.map((d) => (
              <option key={d.id} value={d.id}>
                {divisionLabel(d)}
              </option>
            ))}
          </select>
        </label>
      )}
      <label>
        Your skill: {skill} of 5
        <input type="range" min={signupLimits.minSkill} max={signupLimits.maxSkill} step={1} value={skill} onChange={(e) => setSkill(Number(e.target.value))} />
        <small className="muted">{skillHints[skill]}</small>
      </label>
      {mixed && (
        <fieldset>
          <legend>Gender match</legend>
          {[...genderMatches, null].map((g) => (
            <label key={g ?? "none"} className="check-row">
              <input type="radio" name="gender" checked={gender === g} onChange={() => setGender(g)} />
              {g ? genderMatchLabels[g] : "Prefer not to say"}
            </label>
          ))}
          <small className="muted">Used to even out lines on each team.</small>
        </fieldset>
      )}
      <p className="muted small">Only the host, and the captains if they draft the teams, see your skill and gender match.</p>
      {props.error && <p className="form-error">{props.error}</p>}
      <div className="home-actions">
        <button type="submit" className="btn btn-primary btn-small" disabled={props.busy}>
          {initial ? "Save" : "Sign up"}
        </button>
        <button type="button" className="btn btn-small" onClick={props.onCancel} disabled={props.busy}>
          Cancel
        </button>
      </div>
    </form>
  );
}

// ---- The division's teams (PlayersTab._teams) --------------------------------------------

function DraftedTeams({ user, tournamentId, tournament: t, division: d, manager }: { user: User; tournamentId: string; tournament: TournamentDoc; division: Doc<DivisionDoc>; manager: boolean }) {
  const signups = useSignups(tournamentId, manager).data ?? [];
  const hasGames = useHasGames(tournamentId, manager ? d.id : null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const teams = teamsOf(d);
  const created = teams.length > 0 && teams.every((x) => x.id.startsWith("league_"));
  const acceptedHere = signups.filter((s) => s.divisionId === d.id && s.status === "accepted").length;
  const captains = t.draftMode === "captains";
  const published = isScheduled(t);
  const href = teams.length === 0 && captains ? draftHrefs.liveDraft(tournamentId, d.id) : draftHrefs.teamDraft(tournamentId, d.id);
  const label = teams.length === 0 ? (captains ? "Captains' draft" : "Draft teams") : created ? "View teams" : "Edit teams";

  async function createTeams() {
    if (!window.confirm(`Create ${teams.length} teams? Each team is created with its captain as owner and the other players as members. You won't be able to redraft afterwards; rosters are managed on each team.`)) return;
    await attempt(setBusy, setError, () => draftApi.createLeagueTeams(user, tournamentId, d.id));
  }

  return (
    <section className="card">
      <div className="draft-head">
        <h2 className="card-title">Teams</h2>
        {manager &&
          (acceptedHere < 2 && teams.length === 0 ? (
            <button type="button" className="btn btn-primary btn-small" disabled>
              {label}
            </button>
          ) : (
            <Link className="btn btn-primary btn-small" href={href}>
              {label}
            </Link>
          ))}
      </div>
      {teams.length === 0 && <p className="muted">{manager ? "Accept players below, then draft teams from them." : "Teams are drawn once registration closes."}</p>}
      {manager && t.kind === "league" && teams.length > 0 && !created && !published && (
        <div className="draft-callout">
          <b>Make the teams</b>
          <p>A league plays as real teams, each with chat, a roster and its games on the schedule. Create them from your drafted teams before you publish the schedule.</p>
          {error && <p className="form-error">{error}</p>}
          <button type="button" className="btn btn-primary btn-small" onClick={createTeams} disabled={busy || hasGames === true}>
            {busy ? "Creating…" : "Create teams"}
          </button>
        </div>
      )}
      {manager && created && <p className="muted small">These are real teams: each captain owns theirs and manages its roster.</p>}
      {manager && published && !created && (
        <p className="muted small">The schedule is published: you can still move players, rename teams and change captains, but not add or remove teams.</p>
      )}
      {teams.length > 0 && (
        <ul className="draft-team-list">
          {teams.map((team) => {
            const names = team.playerIds.map((id) => `${team.playerNames[id] || "Player"}${id === team.captainId ? " (C)" : ""}`).join(", ");
            // Members open their team (others can't read it).
            const open = created && team.playerIds.includes(user.uid);
            return (
              <li key={team.id}>
                {open ? <Link href={`/teams/${encodeURIComponent(team.id)}`}>{team.name}</Link> : <b>{team.name}</b>}
                <span className="muted small">{names}</span>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

// ---- Every signup, for the host (PlayersTab._manage) ---------------------------------------

function SignupList({ user, tournamentId, tournament: t, division: d }: { user: User; tournamentId: string; tournament: TournamentDoc; division: Doc<DivisionDoc> }) {
  const signups = useSignups(tournamentId, true);
  const payments = usePayments(tournamentId, true).data ?? [];
  const [unpaidOnly, setUnpaidOnly] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const fee = t.bidFee ?? null;
  const paymentById = new Map(payments.map((x) => [x.id, x]));
  const paidById = new Map(payments.map((x) => [x.id, x.paid === true]));
  const isPaid = (uid: string) => paidById.get(uid) ?? false;
  const all = (signups.data ?? []).filter((s) => s.divisionId === d.id).sort((a, b) => a.name.localeCompare(b.name));
  const owes = (s: PlayerSignupDoc & { id: string }) => s.status !== "withdrawn" && s.status !== "declined";
  const shown = all.filter((s) => !unpaidOnly || (!!fee && owes(s) && !isPaid(s.id)));
  const count = (st: SignupStatus) => all.filter((x) => x.status === st).length;
  // Who is still in: the split and average skill count only them.
  const active = all.filter(owes);
  const mmp = active.filter((x) => x.gender === "mmp").length;
  const wmp = active.filter((x) => x.gender === "wmp").length;
  const avgSkill = active.length ? active.reduce((sum, x) => sum + x.skill, 0) / active.length : null;
  const pending = count("applied");
  const unpaid = !fee || fee.amountCents === 0 ? 0 : (signups.data ?? []).filter((s) => (s.status === "accepted" || s.status === "applied") && !isPaid(s.id)).length;

  async function run(uid: string, fn: () => Promise<unknown>) {
    await attempt((b) => setBusy(b ? uid : null), setError, fn);
  }

  return (
    <section className="card">
      <div className="draft-head">
        <h2 className="card-title">Players</h2>
        {fee && (
          <label className="check-row small">
            <input type="checkbox" checked={unpaidOnly} onChange={(e) => setUnpaidOnly(e.target.checked)} />
            Unpaid ({unpaid})
          </label>
        )}
      </div>
      <div className="draft-summary">
        <b>
          {all.length} signed up · {count("accepted")} accepted{count("waitlisted") > 0 ? ` · ${count("waitlisted")} waitlisted` : ""}
        </b>
        {all.length > 0 && (
          <div className="draft-tiles">
            <div className="draft-tile">
              <b>{count("accepted")}</b>
              <span>Accepted</span>
            </div>
            {/* New signups are the host's to decide. */}
            <div className={`draft-tile${pending > 0 ? " draft-tile-due" : ""}`}>
              <b>{pending}</b>
              <span>To decide</span>
            </div>
            <div className="draft-tile">
              <b>{count("waitlisted")}</b>
              <span>Waitlist</span>
            </div>
          </div>
        )}
        {mmp + wmp > 0 && (
          <>
            <GenderSplit mmp={mmp} wmp={wmp} unknown={active.length - mmp - wmp} />
            <div className="draft-legend">
              <span>
                <i className="draft-dot-mmp" aria-hidden />
                {mmp} MMP
              </span>
              <span>
                <i className="draft-dot-wmp" aria-hidden />
                {wmp} WMP
              </span>
              {active.length > mmp + wmp && (
                <span>
                  <i className="draft-dot-unset" aria-hidden />
                  {active.length - mmp - wmp} not set
                </span>
              )}
              {avgSkill !== null && <span>Avg skill {avgSkill.toFixed(1)}</span>}
            </div>
          </>
        )}
      </div>
      {signups.error && <p className="form-error">{signups.error}</p>}
      {error && <p className="form-error">{error}</p>}
      {shown.length === 0 ? (
        <p className="muted">{all.length === 0 ? "No one has signed up yet." : "Everyone here has paid."}</p>
      ) : (
        <div className="draft-scroll">
          <table className="data-table">
            <thead>
              <tr>
                <th>Player</th>
                <th>Skill</th>
                <th>Status</th>
                {fee && <th>Fee</th>}
                <th className="narrow">Decide</th>
              </tr>
            </thead>
            <tbody>
              {shown.map((s) => (
                <tr key={s.id} className={s.status === "applied" ? "draft-row-due" : undefined}>
                  <td>
                    <b>{s.name}</b>
                  </td>
                  <td>
                    {s.skill}
                    {s.gender ? ` · ${genderMatchLabels[s.gender]}` : ""}
                  </td>
                  <td>
                    <StatusPill status={s.status} />
                  </td>
                  {fee && (
                    <td>
                      {owes(s) && (
                        <HostPaymentControls user={user} tournamentId={tournamentId} payerId={s.id} payment={paymentById.get(s.id)} overdue={overdue(fee, false)} />
                      )}
                    </td>
                  )}
                  <td className="narrow">
                    <select
                      aria-label={`Change ${s.name}'s status`}
                      value=""
                      disabled={busy === s.id}
                      onChange={(e) => e.target.value && run(s.id, () => draftApi.setStatus(user, tournamentId, s.id, e.target.value as SignupStatus))}
                    >
                      <option value="">Change…</option>
                      {(["accepted", "waitlisted", "declined"] as const)
                        .filter((st) => st !== s.status)
                        .map((st) => (
                          <option key={st} value={st}>
                            {st === "accepted" ? "Accept" : st === "waitlisted" ? "Waitlist" : "Decline"}
                          </option>
                        ))}
                    </select>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
