"use client";
// Hosting a tournament or league, or editing its details, format and
// divisions, a step at a time with Save draft / Publish (HostedTournamentFormScreen and
// EventFormatSection in the app). A new event is a tournament or a league,
// and teams apply or players sign up; that's fixed once it's created.
import {
  currencies,
  type DivisionDoc,
  type Division,
  divisionLabels,
  divisions as allDivisions,
  draftModeLabels,
  defaultInviteReplyDays,
  inviteReplyChoices,
  inviteReplyLabel,
  type DraftMode,
  type EntryDoc,
  type FormFormat,
  type HostedKind,
  type HostedType,
  type TournamentDoc,
  type TournamentEntryType,
  type TournamentVisibility,
  competitionLevels,
  engineSeason,
  engineSettings,
  formatOn,
  formatRequest,
  levelLabels,
  seasonEnd,
  statusIndex,
  tournamentFormatLabels,
  tournamentFormats,
  tournamentLimits,
  usualFormat,
  visibilityLabels,
  type CompetitionLevel,
  type EngineSeason,
  type TournamentFormat,
  entryChoiceLabels,
  entryChoiceOf,
  entryChoicesFor,
  entryFields,
  directorSchema,
  entryDeadlineProblem,
} from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { useAuth } from "@/components/AuthProvider";
import { FeeBreakdownNote, PayoutsCard, usePaymentFees } from "@/components/payments/Payments";
import { DirectorStep } from "./DirectorStep";
import type { TeamDoc } from "@/components/team/TeamContext";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { tournamentHref } from "./TournamentLists";
import { canOn, tournamentPath, useAction } from "./useTournament";
import "./tournaments.css";
import { formatDate } from "@/lib/dates";

const pad = (n: number) => String(n).padStart(2, "0");
const dayValue = (d: Date | null) => (d ? `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` : "");
const fromDay = (v: string): Date | null => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null;
};
const timeValue = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const centsOf = (amount: string): number | null => {
  const v = Number(amount.trim().replace(/^\$/, ""));
  if (amount.trim() === "" || !Number.isFinite(v) || v < 0 || v > 100000) return null;
  return Math.round(v * 100);
};
const amountOf = (cents: number) => (cents / 100).toFixed(cents % 100 === 0 ? 0 : 2);
const defaultSeason: EngineSeason = { weeks: 8, playoffWeeks: 1, playoffTeams: 4, gamesPerNight: 1, skipDates: [] };

/** A month out on a Saturday, like most club events. */
function firstSaturday(): Date {
  const t = new Date();
  const d = new Date(t.getFullYear(), t.getMonth(), t.getDate() + 30);
  while (d.getDay() !== 6) d.setDate(d.getDate() + 1);
  return d;
}

interface FormState {
  name: string;
  description: string;
  location: string;
  startsOn: Date;
  endsOn: Date | null;
  visibility: TournamentVisibility;
  hasFee: boolean;
  feeAmount: string;
  currency: string;
  instructions: string;
  feeDue: Date | null;
  /** Paid online, payers also pay the processing fees. */
  payerCoversFees: boolean;
  kind: HostedKind;
  entryType: TournamentEntryType;
  draftMode: DraftMode;
  /** Days before the start invited teams answer by, or null. */
  inviteReplyDays: number | null;
  season: EngineSeason;
  teamEntry: boolean;
  teamFeeAmount: string;
  format: FormFormat;
  wanted: Division[];
  /** When rosters and fees are due (entryDeadline); the fee's due date follows it. */
  entryDeadline: Date | null;
  director: DirectorForm | null;
}

/** The director as the form edits them: a member (uid) or anyone by name. */
export interface DirectorForm {
  uid: string | null;
  name: string;
  email: string;
  phone: string;
}

function blank(type: HostedType | null): FormState {
  const start = firstSaturday();
  const kind: HostedKind = type === "league" ? "league" : "tournament";
  const endsOn = kind === "league" ? seasonEnd(start, defaultSeason) : new Date(start.getFullYear(), start.getMonth(), start.getDate() + 1);
  return {
    name: "",
    description: "",
    location: "",
    startsOn: start,
    endsOn,
    visibility: "public",
    hasFee: false,
    feeAmount: "",
    currency: "USD",
    instructions: "",
    feeDue: null,
    payerCoversFees: false,
    kind,
    entryType: type === "hat" ? "players" : "teams",
    draftMode: "balanced",
    inviteReplyDays: defaultInviteReplyDays,
    season: defaultSeason,
    teamEntry: false,
    teamFeeAmount: "",
    format: usualFormat({ kind, startsOn: start, endsOn }),
    wanted: ["mixed"],
    entryDeadline: null,
    director: null,
  };
}

function filled(t: TournamentDoc, divisions: Array<Doc<DivisionDoc>>): FormState {
  const startsOn = new Date(t.startsOn);
  const endsOn = t.endsOn ? new Date(t.endsOn) : null;
  const kind = t.kind ?? "tournament";
  const first = divisions[0];
  const format: FormFormat = t.format
    ? { settings: engineSettings(t.format.settings), level: t.format.level, maxTeams: t.format.maxTeams, minRoster: t.format.minRoster ?? null }
    : first
      ? { settings: engineSettings(first.settings), level: first.level, maxTeams: first.maxTeams, minRoster: first.minRoster ?? null }
      : usualFormat({ kind, startsOn, endsOn });
  return {
    name: t.name,
    description: t.description ?? "",
    location: t.location ?? "",
    startsOn,
    endsOn,
    visibility: t.visibility,
    hasFee: !!t.bidFee,
    feeAmount: t.bidFee ? amountOf(t.bidFee.amountCents) : "",
    currency: t.bidFee?.currency ?? "USD",
    instructions: t.bidFee?.instructions ?? "",
    feeDue: t.bidFee?.dueAt ? new Date(t.bidFee.dueAt) : null,
    payerCoversFees: t.bidFee?.payerCoversFees === true,
    kind,
    entryType: t.entryType,
    draftMode: t.draftMode ?? "balanced",
    inviteReplyDays: t.inviteReplyDays ?? null,
    season: engineSeason(t.season) ?? defaultSeason,
    teamEntry: t.teamEntry === true,
    teamFeeAmount: t.teamFee ? amountOf(t.teamFee.amountCents) : "",
    format,
    wanted: divisions.map((d) => d.division),
    entryDeadline: t.entryDeadline ? new Date(t.entryDeadline) : t.bidFee?.dueAt ? new Date(t.bidFee.dueAt) : null,
    director: t.director ? { uid: t.director.uid ?? null, name: t.director.name, email: t.director.email ?? "", phone: t.director.phone ?? "" } : null,
  };
}

/** Whether the event takes teams (so it can invite them). */
const takesTeamsOf = (f: FormState) => f.entryType === "teams" || f.teamEntry;

/** Why the form can't be saved yet (problem in the app). */
function problemOf(f: FormState): string | null {
  const players = f.entryType === "players";
  if (!f.name.trim()) return "Give it a name.";
  if (f.hasFee && centsOf(f.feeAmount) == null) return `Enter the ${players ? "entry fee" : "bid fee"}, e.g. 250.`;
  if (f.hasFee && players && f.teamEntry && centsOf(f.teamFeeAmount) == null) return "Enter the team spot fee, e.g. 300.";
  if (f.wanted.length === 0) return "Open at least one division.";
  const late = entryDeadlineProblem(f.entryDeadline, f.startsOn);
  if (late) return late;
  if (f.director) {
    const d = directorSchema.safeParse(f.director);
    if (!d.success) return d.error.issues[0]?.message ?? "Check the director's details.";
  }
  if (f.kind === "league" && f.season.playoffTeams > 0) {
    if (f.season.playoffWeeks < 1) return "Give the playoffs at least one week.";
    if (f.season.playoffWeeks >= f.season.weeks) return "Leave at least one week for the regular season.";
  }
  return null;
}

/** The request the API takes. */
function requestOf(f: FormState) {
  const players = f.entryType === "players";
  const teamEntry = players && f.teamEntry;
  const season = f.kind === "league" ? f.season : null;
  const fee = f.hasFee
    ? { amountCents: centsOf(f.feeAmount) ?? 0, currency: f.currency, instructions: f.instructions.trim(), dueAt: f.entryDeadline?.toISOString() ?? null, payerCoversFees: f.payerCoversFees }
    : null;
  return {
    name: f.name.trim(),
    description: f.description.trim(),
    location: f.location.trim(),
    startsOn: f.startsOn.toISOString(),
    endsOn: f.endsOn?.toISOString() ?? null,
    visibility: f.visibility,
    bidFee: fee,
    teamEntry,
    teamFee: fee && teamEntry ? { ...fee, amountCents: centsOf(f.teamFeeAmount) ?? 0 } : null,
    season: season ? { ...season, skipDates: season.skipDates.map((d) => d.toISOString()) } : null,
    draftMode: f.draftMode,
    inviteReplyDays: takesTeamsOf(f) ? f.inviteReplyDays : null,
    format: formatRequest(formatOn(f.format, { kind: f.kind, startsOn: f.startsOn, endsOn: f.endsOn, season })),
    divisions: allDivisions.filter((d) => f.wanted.includes(d)),
    entryDeadline: f.entryDeadline?.toISOString() ?? null,
    director: f.director ? { ...f.director, name: f.director.name.trim(), email: f.director.email.trim(), phone: f.director.phone.trim() } : null,
  };
}

/** /tournaments/new?host=…&type=… and /tournaments/:id/edit. */
/** Under the location and About (the app says the same): published events are on the public website. */
export const publicDetailsHint = "The location and About are public: anyone can see them once it's published, even without an account.";

export function TournamentForm({ hostId, tournamentId, type }: { hostId?: string; tournamentId?: string; type?: HostedType | null }) {
  const { user } = useAuth();
  const paymentFees = usePaymentFees(user);
  const router = useRouter();
  const isNew = !tournamentId;
  const existing = useLiveDoc<TournamentDoc>(user && tournamentId ? `tournaments/${tournamentId}` : null);
  const hostKey = hostId ?? existing.data?.hostId ?? null;
  const host = useLiveDoc<TeamDoc & { official?: boolean }>(user && hostKey ? `teams/${hostKey}` : null);
  const divRows = useLiveQuery<DivisionDoc>(user && tournamentId ? `tournaments/${tournamentId}/divisions` : null, [], tournamentId ?? "");
  const entryRows = useLiveQuery<EntryDoc>(user && tournamentId ? `tournaments/${tournamentId}/entries` : null, [], tournamentId ?? "");
  // Only managers read signups; a division someone has signed up for stays open.
  const signupRows = useLiveQuery<{ divisionId: string; status: string }>(user && tournamentId ? `tournaments/${tournamentId}/signups` : null, [], tournamentId ?? "");
  const [form, setForm] = useState<FormState | null>(isNew ? blank(type ?? null) : null);
  // The step showing (formSteps); the last is Review. Each step starts at the top.
  const [step, setStepState] = useState(0);
  const setStep = (next: number) => {
    setStepState(next);
    window.scrollTo({ top: 0 });
  };
  const { busy, error, run } = useAction();
  // A new event created as a draft whose Publish then failed: further saves update it (the app's createdDraftId).
  const [createdId, setCreatedId] = useState<string | null>(null);

  useEffect(() => {
    if (form || !existing.data || !divRows.data) return;
    const order = existing.data.divisions.map((s) => divRows.data?.find((d) => d.id === s.id)).filter((d): d is Doc<DivisionDoc> => !!d);
    setForm(filled(existing.data, order));
  }, [form, existing.data, divRows.data]);

  const taken = useMemo(
    () =>
      new Set([
        ...(entryRows.data ?? []).filter((e) => e.status !== "withdrawn" && e.status !== "declined").map((e) => e.divisionId),
        ...(signupRows.data ?? []).filter((s) => s.status !== "withdrawn" && s.status !== "declined").map((s) => s.divisionId),
      ]),
    [entryRows.data, signupRows.data],
  );

  if (!isNew && existing.data === null) return <p className="empty">That tournament doesn&apos;t exist or you can&apos;t see it.</p>;
  if (existing.error || host.error) return <p className="form-error">{existing.error ?? host.error}</p>;
  if (!form || host.data === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
  const canHost = canOn(host.data, user?.uid, "manageEvents");
  if (!canHost) return <p className="empty">Only members who manage events can host tournaments.</p>;

  const f = form;
  const set = (patch: Partial<FormState>) => setForm({ ...f, ...patch });
  const league = f.kind === "league";
  const players = f.entryType === "players";
  const choice = entryChoiceOf(f);
  const s = f.format.settings;
  const editable = statusIndex(existing.data?.status ?? "draft") < statusIndex("scheduled");
  const setSettings = (patch: Partial<FormFormat["settings"]>) => set({ format: { ...f.format, settings: { ...s, ...patch } } });
  const setSeason = (season: EngineSeason) => set({ season, endsOn: seasonEnd(f.startsOn, season) });
  const problem = problemOf(f);
  // Still a draft (or not created yet): Save draft and Publish. A published
  // event has a single Save, so editing it never changes where it stands.
  const isDraft = isNew || existing.data?.status === "draft";
  const lockedReason = (d: Division): string | null => {
    const div = divRows.data?.find((x) => x.division === d);
    if (!div) return null;
    if (div.seeds.length > 0 || (div.teams ?? []).length > 0) return "It has teams. Remove them on the event page first.";
    if (taken.has(div.id)) return "People have signed up for it.";
    return null;
  };

  /**
   * Save draft (a new event starts as a draft only the host's managers
   * see), Save, or with [publish] also open registration, as the event
   * page's "Publish and open registration" does. A new event that was
   * created but couldn't be published stays on the form with the error,
   * and the next save updates that draft, so it isn't created twice.
   */
  async function save(publish: boolean) {
    if (problem) return;
    let id = tournamentId ?? createdId;
    if (isNew && !createdId) {
      const res = await run<{ id: string }>("/v1/tournaments", "POST", { hostId, kind: f.kind, entryType: f.entryType, ...requestOf(f) });
      if (!res.ok) return;
      id = res.value.id;
    } else if (id) {
      const res = await run(tournamentPath(id), "PATCH", requestOf(f));
      if (!res.ok) return;
    }
    if (!id) return;
    if (publish) {
      const res = await run(`${tournamentPath(id)}/status`, "PUT", { status: "registration" });
      if (!res.ok) {
        if (isNew) setCreatedId(id);
        return;
      }
    }
    router.push(tournamentHref(id));
  }

  const number = (label: string, value: number, options: number[], onChange: (v: number) => void, text?: (v: number) => string) => (
    <label>
      {label}
      <select value={value} disabled={!editable} onChange={(e) => onChange(Number(e.target.value))}>
        {[...new Set([...options, value])]
          .sort((a, b) => a - b)
          .map((o) => (
            <option key={o} value={o}>
              {text ? text(o) : o}
            </option>
          ))}
      </select>
    </label>
  );

  return (
    <form className="stack hosted-form" onSubmit={(e) => e.preventDefault()}>
      <StepHeader step={step} onStep={setStep} />
      {step === 0 && (
        <section className="card settings-form">
          <h2 className="card-title">Details</h2>
          {host.data?.name && <small className="muted">Hosted by {host.data.name}</small>}
          {isNew ? (
            <div className="segmented" role="group" aria-label="Kind">
              {(["tournament", "league"] as HostedKind[]).map((k) => (
                <button
                  key={k}
                  type="button"
                  className={f.kind === k ? "on" : ""}
                  onClick={() => {
                    const endsOn = k === "league" ? seasonEnd(f.startsOn, f.season) : new Date(f.startsOn.getFullYear(), f.startsOn.getMonth(), f.startsOn.getDate() + 1);
                    set({ kind: k, endsOn, format: usualFormat({ kind: k, startsOn: f.startsOn, endsOn }) });
                  }}
                >
                  {k === "league" ? "League" : "Tournament"}
                </button>
              ))}
            </div>
          ) : (
            <p>
              <span className="pill">{league ? "League" : "Tournament"}</span> <span className="pill">{entryChoiceLabels[choice]}</span>
            </p>
          )}
          <label>
            Name
            <input value={f.name} maxLength={tournamentLimits.name} placeholder="e.g. Spring Fling" onChange={(e) => set({ name: e.target.value })} />
          </label>
          <label>
            About
            <textarea rows={4} value={f.description} maxLength={tournamentLimits.description} placeholder="Format, parking, food, contacts…" onChange={(e) => set({ description: e.target.value })} />
          </label>
          <p className="muted small">{publicDetailsHint}</p>
        </section>
      )}
      {step === 1 && (
        <>
          <section className="card settings-form">
            <h2 className="card-title">When &amp; where</h2>
            {league ? (
              <label>
                First night
                <input
                  type="date"
                  value={dayValue(f.startsOn)}
                  onChange={(e) => {
                    const d = fromDay(e.target.value);
                    if (d) set({ startsOn: d, endsOn: seasonEnd(d, f.season) });
                  }}
                />
                {f.endsOn && <small className="muted">Last night {formatDate(f.endsOn, { weekday: "short", month: "short", day: "numeric", year: "numeric" })}</small>}
              </label>
            ) : (
              <div className="form-grid">
                <label>
                  First day
                  <input
                    type="date"
                    value={dayValue(f.startsOn)}
                    onChange={(e) => {
                      const d = fromDay(e.target.value);
                      if (d) set({ startsOn: d, endsOn: f.endsOn && f.endsOn < d ? null : f.endsOn });
                    }}
                  />
                </label>
                <label>
                  Last day
                  <input
                    type="date"
                    value={dayValue(f.endsOn ?? f.startsOn)}
                    min={dayValue(f.startsOn)}
                    onChange={(e) => {
                      const d = fromDay(e.target.value);
                      if (d) set({ endsOn: d.getTime() === f.startsOn.getTime() ? null : d });
                    }}
                  />
                </label>
              </div>
            )}
            <label>
              Location
              <input value={f.location} maxLength={tournamentLimits.location} placeholder="Fields or park, city" onChange={(e) => set({ location: e.target.value })} />
            </label>
          </section>
          {league && (
            <section className="card settings-form">
              <h2 className="card-title">Season</h2>
              <div className="form-grid">
                {number("Weeks", f.season.weeks, Array.from({ length: tournamentLimits.maxWeeks }, (_, i) => i + 1), (weeks) => setSeason({ ...f.season, weeks }), (v) => `${v} weeks`)}
                {number("Games a night", f.season.gamesPerNight, [1, 2], (gamesPerNight) => setSeason({ ...f.season, gamesPerNight }))}
                {number(
                  "Playoffs",
                  f.season.playoffTeams,
                  [...tournamentLimits.playoffSizes],
                  (playoffTeams) => setSeason({ ...f.season, playoffTeams, playoffWeeks: playoffTeams === 0 ? 0 : f.season.playoffWeeks || 1 }),
                  (v) => (v === 0 ? "None" : `Top ${v}`),
                )}
                {f.season.playoffTeams > 0 &&
                  number("Playoff weeks (the last weeks)", f.season.playoffWeeks, [1, 2, 3], (playoffWeeks) => setSeason({ ...f.season, playoffWeeks }))}
              </div>
              <fieldset>
                <legend>Skipped weeks</legend>
                <div className="hosted-chips">
                  {f.season.skipDates.map((d) => (
                    <button
                      key={d.getTime()}
                      type="button"
                      className="pill"
                      aria-label={`Don't skip ${d.toDateString()}`}
                      onClick={() => setSeason({ ...f.season, skipDates: f.season.skipDates.filter((x) => x.getTime() !== d.getTime()) })}
                    >
                      {formatDate(d, { month: "short", day: "numeric" })} ✕
                    </button>
                  ))}
                  {f.season.skipDates.length < tournamentLimits.maxSkipDates && (
                    <input
                      type="date"
                      aria-label="Skip a week"
                      min={dayValue(f.startsOn)}
                      value=""
                      onChange={(e) => {
                        const d = fromDay(e.target.value);
                        if (d && !f.season.skipDates.some((x) => x.getTime() === d.getTime())) setSeason({ ...f.season, skipDates: [...f.season.skipDates, d] });
                      }}
                    />
                  )}
                </div>
                <small className="muted">A night with no games, e.g. a holiday. The season runs a week longer.</small>
              </fieldset>
            </section>
          )}
        </>
      )}
      {step === 2 && (
        <section className="card settings-form">
          <h2 className="card-title">Who can play</h2>
          {isNew && (
            <>
              <div className="segmented" role="group" aria-label="Who enters">
                {entryChoicesFor(f.kind).map((k) => (
                  <button key={k} type="button" className={choice === k ? "on" : ""} onClick={() => set(entryFields(k))}>
                    {entryChoiceLabels[k]}
                  </button>
                ))}
              </div>
              <p className="muted small">
                {league
                  ? choice === "both"
                    ? "A weekly league: a captain can pay the team fee and bring their own team, or players sign up on their own and are drafted onto the other teams."
                    : players
                    ? "A weekly league: players sign up on their own and are drafted onto teams, which become real teams with chat and a roster."
                    : "A weekly league for teams that apply, with a minimum roster."
                  : players
                    ? "A hat tournament: players sign up on their own and are drafted onto teams."
                    : "A weekend tournament for teams that apply."}
              </p>
            </>
          )}
          {players && (
            <>
              {/* A league picks this as its third choice above; a tournament keeps the switch. */}
              {!league && (
              <label className="switch-row">
                <input type="checkbox" checked={f.teamEntry} onChange={(e) => set({ teamEntry: e.target.checked })} />
                <span>
                  Teams can also reserve a spot
                  <small className="muted">
                    {" "}
                    A captain pays the team fee, names their team and invites their own players. Everyone else signs up on their own
                    and is drafted into the remaining spots.
                  </small>
                </span>
              </label>
              )}
              <fieldset>
                <legend>How teams are made</legend>
                <div className="segmented" role="group">
                  {(["balanced", "captains"] as DraftMode[]).map((m) => (
                    <button key={m} type="button" className={f.draftMode === m ? "on" : ""} onClick={() => set({ draftMode: m })}>
                      {draftModeLabels[m].label}
                    </button>
                  ))}
                </div>
                <small className="muted">
                  {f.draftMode === "captains"
                    ? "You choose the captains, who take turns picking players in a live draft. Each captain owns their team."
                    : "Teams are dealt evened out by skill and gender."}
                </small>
              </fieldset>
            </>
          )}
          <div className="segmented" role="group" aria-label="Who can play">
            {(["public", "inviteOnly"] as TournamentVisibility[]).map((v) => (
              <button key={v} type="button" className={f.visibility === v ? "on" : ""} onClick={() => set({ visibility: v })}>
                {visibilityLabels[v].label}
              </button>
            ))}
          </div>
          <small className="muted">{visibilityLabels[f.visibility].summary}. The page, schedule, results and news are public either way.</small>
          {takesTeamsOf(f) && (
            <label>
              <span className="field-label">Invited teams answer by</span>
              <select
                value={f.inviteReplyDays ?? ""}
                onChange={(e) => set({ inviteReplyDays: e.target.value ? Number(e.target.value) : null })}
              >
                {[null, ...inviteReplyChoices].map((d) => (
                  <option key={d ?? "none"} value={d ?? ""}>
                    {inviteReplyLabel(d)}
                  </option>
                ))}
              </select>
              <small className="muted">After this an invite expires and you can invite another team. A late invite still gets two days.</small>
            </label>
          )}
        </section>
      )}
      {step === 3 && (
        <section className="card settings-form">
          <h2 className="card-title">Format</h2>
          <p className="muted small">
            {editable ? "Every division plays this. Change it here and every division follows, until its schedule is out." : "The schedule is out, so the format is set."}
          </p>
          <fieldset disabled={!editable}>
            <legend>Players on the field</legend>
            <div className="segmented" role="group">
              {tournamentLimits.fieldSizes.map((n) => (
                <button
                  key={n}
                  type="button"
                  className={s.playersOnField === n ? "on" : ""}
                  onClick={() => {
                    // The roster minimum follows the field size while it was still the usual one.
                    const usual = f.format.minRoster == null || f.format.minRoster === s.playersOnField;
                    set({ format: { ...f.format, settings: { ...s, playersOnField: n }, minRoster: usual ? n : f.format.minRoster } });
                  }}
                >
                  {n}v{n}
                </button>
              ))}
            </div>
          </fieldset>
          <div className="form-grid">
            <label>
              Level
              <select value={f.format.level} disabled={!editable} onChange={(e) => set({ format: { ...f.format, level: e.target.value as CompetitionLevel } })}>
                {competitionLevels.map((l) => (
                  <option key={l} value={l}>
                    {levelLabels[l]}
                  </option>
                ))}
              </select>
            </label>
            {number("Teams per division", f.format.maxTeams, [...tournamentLimits.teamCaps], (maxTeams) => set({ format: { ...f.format, maxTeams } }), (v) => `${v} teams`)}
            {(!players || f.teamEntry) &&
              number(
                "Roster minimum",
                f.format.minRoster ?? s.playersOnField,
                Array.from({ length: 19 }, (_, i) => i + 2),
                (minRoster) => set({ format: { ...f.format, minRoster } }),
                (v) => `${v} players`,
              )}
            <label>
              {league ? "Game night starts" : "First game each day"}
              <input
                type="time"
                disabled={!editable}
                value={timeValue(s.startsAt)}
                onChange={(e) => {
                  const [h, m] = e.target.value.split(":").map(Number);
                  if (Number.isFinite(h) && Number.isFinite(m)) setSettings({ startsAt: new Date(s.startsAt.getFullYear(), s.startsAt.getMonth(), s.startsAt.getDate(), h, m) });
                }}
              />
              {league && <small className="muted">Weekly, on the first night&apos;s day.</small>}
            </label>
            {!league && (
              <label>
                Format
                <select value={s.format} disabled={!editable} onChange={(e) => setSettings({ format: e.target.value as TournamentFormat })}>
                  {tournamentFormats.map((x) => (
                    <option key={x} value={x}>
                      {tournamentFormatLabels[x].label}
                    </option>
                  ))}
                </select>
                <small className="muted">{tournamentFormatLabels[s.format].summary}</small>
              </label>
            )}
            {!league &&
              (s.format === "poolsSingleElim" || s.format === "poolsPlacement") &&
              number("Pools", s.poolCount, [1, 2, 3, 4, 5, 6, 8], (poolCount) => setSettings({ poolCount }), (v) => (v === 1 ? "One pool" : `${v} pools`))}
          </div>
          <fieldset disabled={!editable}>
            <legend>Scoring</legend>
            <div className="segmented" role="group">
              {(["points", "time"] as const).map((m) => (
                <button key={m} type="button" className={s.scoring === m ? "on" : ""} onClick={() => setSettings({ scoring: m })}>
                  {m === "points" ? "Game to a score" : "Timed"}
                </button>
              ))}
            </div>
            <small className="muted">
              {s.scoring === "time"
                ? "Most points when time runs out wins. Tied at time, they play one more point."
                : "First to the score wins; the time cap keeps the day on schedule."}
            </small>
          </fieldset>
          <div className="form-grid">
            {s.scoring === "time"
              ? number("Game length", s.gameMinutes, [15, 20, 25, 30, 40, 45, 50, 60, 75, 90], (gameMinutes) => setSettings({ gameMinutes }), (v) => `${v} min`)
              : number("Game to", s.scoreCap, [5, 7, 9, 11, 13, 15, 17, 21], (scoreCap) => setSettings({ scoreCap }))}
            {s.scoring === "time"
              ? null
              : number("Time cap", s.gameMinutes, [20, 25, 30, 40, 45, 50, 60, 75, 90, 100, 120], (gameMinutes) => setSettings({ gameMinutes }), (v) => `${v} min`)}
            {number("Timeouts per half", s.timeoutsPerHalf, [0, 1, 2, 3], (timeoutsPerHalf) => setSettings({ timeoutsPerHalf }))}
            {number("Fields", s.fields, Array.from({ length: 16 }, (_, i) => i + 1), (fields) => setSettings({ fields }))}
            {number("Break between games", s.breakMinutes, [0, 5, 10, 15, 20, 30], (breakMinutes) => setSettings({ breakMinutes }), (v) => `${v} min`)}
          </div>
          <fieldset>
            <legend>Divisions</legend>
            <small className="muted">Tick each division to open. Each takes its own {players ? "signups" : "teams"} and gets its own schedule.</small>
            {allDivisions.map((d) => {
              const on = f.wanted.includes(d);
              const reason = on ? lockedReason(d) : null;
              return (
                <label key={d} className="switch-row">
                  <input
                    type="checkbox"
                    checked={on}
                    disabled={!!reason}
                    onChange={(e) => set({ wanted: e.target.checked ? [...f.wanted, d] : f.wanted.filter((x) => x !== d) })}
                  />
                  <span>
                    {levelLabels[f.format.level]} {divisionLabels[d]}
                    {reason && <small className="muted"> {reason}</small>}
                  </span>
                </label>
              );
            })}
          </fieldset>
        </section>
      )}
      {step === 4 && (
        <section className="card settings-form">
          <h2 className="card-title">Fees &amp; deadline</h2>
          <label>
            {players ? "Sign-ups and fees due" : "Rosters and fees due"}
            <input
              type="date"
              value={dayValue(f.entryDeadline)}
              max={dayValue(f.startsOn)}
              onChange={(e) => {
                const d = fromDay(e.target.value);
                set({ entryDeadline: d ? new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59) : null });
              }}
            />
            <small className="muted">
              {f.entryDeadline ? "" : "Without one, it's the day before the event. "}
              {players ? "Players" : "Teams"} get a reminder 3 days before, and you see who&apos;s missing.
            </small>
          </label>
          <label className="switch-row">
            <input type="checkbox" checked={f.hasFee} onChange={(e) => set({ hasFee: e.target.checked })} />
            <span>
              {players ? "Entry fee" : "Bid fee"}
              <small className="muted">
                {" "}
                {players && f.teamEntry
                  ? "What each player who signs up pays, and what a team pays to reserve a spot. You mark them paid, or Stall 10 does when they pay online."
                  : players
                    ? "What each player pays to sign up. You mark them paid, or Stall 10 does when they pay online."
                    : "What each team pays to hold its spot. You mark them paid, or Stall 10 does when they pay online."}
              </small>
            </span>
          </label>
          {f.hasFee && (
            <>
              <div className="form-grid">
                <label>
                  {players && f.teamEntry ? "Per player" : "Amount"}
                  <input inputMode="decimal" placeholder="250" value={f.feeAmount} onChange={(e) => set({ feeAmount: e.target.value })} />
                </label>
                <label>
                  Currency
                  <select value={f.currency} onChange={(e) => set({ currency: e.target.value })}>
                    {[...new Set([...currencies, f.currency])].map((c) => (
                      <option key={c}>{c}</option>
                    ))}
                  </select>
                </label>
                {players && f.teamEntry && (
                  <label>
                    Per team spot
                    <input inputMode="decimal" placeholder="300" value={f.teamFeeAmount} onChange={(e) => set({ teamFeeAmount: e.target.value })} />
                  </label>
                )}
              </div>
              <FeeBreakdownNote user={user} amountCents={centsOf(f.feeAmount)} currency={f.currency} />
              {players && f.teamEntry && <FeeBreakdownNote user={user} amountCents={centsOf(f.teamFeeAmount)} currency={f.currency} />}
              {/* Whether the host can take payments online, with setup right here. */}
              {user && hostKey && <PayoutsCard user={user} teamId={hostKey} amountCents={centsOf(f.feeAmount) ?? undefined} />}
              {/* With online payments on, these are the other ways (a school's check or PO). */}
              <label>
                {paymentFees?.available ? "Other ways to pay" : "How to pay"}
                <textarea
                  rows={2}
                  maxLength={tournamentLimits.feeInstructions}
                  placeholder={paymentFees?.available ? "e.g. Checks payable to Fling Crew, mailed to 12 Main St" : "e.g. Venmo @club-treasurer with your team name"}
                  value={f.instructions}
                  onChange={(e) => set({ instructions: e.target.value })}
                />
              </label>
            </>
          )}
        </section>
      )}
      {step === directorStep && user && <DirectorStep user={user} f={f} host={host.data} onChange={(director) => set({ director })} />}
      {step === lastStep && <Review f={f} onEdit={setStep} />}

      {step === lastStep && isDraft && (
        <p className="muted small">Save draft keeps it to your managers. Publish puts it on the website and opens registration for {players ? "signups" : "teams"}.</p>
      )}
      {step === lastStep && problem && <p className="hosted-form-problem">{problem}</p>}
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions hosted-form-nav">
        {step > 0 && (
          <button type="button" className="btn" onClick={() => setStep(step - 1)}>
            Back
          </button>
        )}
        {step < lastStep ? (
          <button type="button" className="btn btn-primary" onClick={() => setStep(step + 1)}>
            Next: {formSteps[step + 1]}
          </button>
        ) : (
          <button type="button" className="btn btn-primary" disabled={busy || !!problem} onClick={() => void save(isDraft)}>
            {isDraft ? "Publish" : "Save"}
          </button>
        )}
        {/* Saving never needs the last step. */}
        {(isDraft || step < lastStep) && (
          <button type="button" className="btn btn-quiet" disabled={busy || !!problem} onClick={() => void save(false)}>
            {isDraft ? "Save draft" : "Save"}
          </button>
        )}
        <Link className="btn btn-quiet" href={tournamentId ? tournamentHref(tournamentId) : hostId ? `/teams/${encodeURIComponent(hostId)}/tournaments` : "/tournaments"}>
          Cancel
        </Link>
      </div>
    </form>
  );
}

/** The form's steps, in order (HostedTournamentFormViewModel.steps in the app); the last is Review. */
const formSteps = ["Details", "When & where", "Who can play", "Format & divisions", "Fees & deadline", "Director", "Review"] as const;
const directorStep = 5;
const lastStep = formSteps.length - 1;

/** "Step 2 of 6 · When & where" over a bar of the steps; a step's segment jumps to it. */
function StepHeader({ step, onStep }: { step: number; onStep: (step: number) => void }) {
  return (
    <div className="form-steps">
      <b className="form-steps-title">
        Step {step + 1} of {formSteps.length} · {formSteps[step]}
      </b>
      <div className="form-steps-bar">
        {formSteps.map((title, i) => (
          <button
            key={title}
            type="button"
            className={i <= step ? "on" : ""}
            aria-label={`Step ${i + 1}: ${title}`}
            aria-current={i === step ? "step" : undefined}
            onClick={() => onStep(i)}
          />
        ))}
      </div>
    </div>
  );
}

/** The last step: everything at a glance, each part with Edit to go back to its step. */
function Review({ f, onEdit }: { f: FormState; onEdit: (step: number) => void }) {
  const players = f.entryType === "players";
  const league = f.kind === "league";
  const day = (d: Date) => formatDate(d, { weekday: "short", month: "short", day: "numeric", year: "numeric" });
  const money = (amount: string) => {
    const cents = centsOf(amount);
    return cents == null ? "amount missing" : `${amountOf(cents)} ${f.currency}`;
  };
  const rows: Array<[number, string, string]> = [
    [0, "Details", [f.name.trim() || "No name yet", league ? "League" : "Tournament"].join(" · ")],
    [
      1,
      "When & where",
      [f.endsOn && f.endsOn.getTime() !== f.startsOn.getTime() ? `${day(f.startsOn)} – ${day(f.endsOn)}` : day(f.startsOn), f.location.trim()]
        .filter(Boolean)
        .join(" · "),
    ],
    [
      2,
      "Who can play",
      [entryChoiceLabels[entryChoiceOf(f)], players && f.teamEntry && f.kind !== "league" ? "teams can reserve a spot" : "", visibilityLabels[f.visibility].label]
        .filter(Boolean)
        .join(" · "),
    ],
    [
      3,
      "Format & divisions",
      [
        league ? "Weekly" : tournamentFormatLabels[f.format.settings.format].label,
        `${f.format.settings.playersOnField}v${f.format.settings.playersOnField}`,
        `${f.wanted.length} ${f.wanted.length === 1 ? "division" : "divisions"}`,
      ].join(" · "),
    ],
    [
      4,
      "Fees & deadline",
      !f.hasFee
        ? "No fee"
        : [`${players ? "Entry fee" : "Bid fee"}: ${money(f.feeAmount)}`, players && f.teamEntry ? `team spot: ${money(f.teamFeeAmount)}` : ""]
            .filter(Boolean)
            .join(" · ") + (f.entryDeadline ? ` · due ${day(f.entryDeadline)}` : ""),
    ],
    [5, "Director", f.director ? [f.director.name || "Name missing", f.director.uid ? "Stall 10 member" : f.director.email || f.director.phone].filter(Boolean).join(" · ") : "None"],
  ];
  return (
    <section className="card settings-form">
      <h2 className="card-title">Review</h2>
      <dl className="form-review">
        {rows.map(([i, title, value]) => (
          <div key={title} className="form-review-row">
            <div>
              <dt>{title}</dt>
              <dd>{value}</dd>
            </div>
            <button type="button" className="text-btn" aria-label={`Edit ${title}`} onClick={() => onEdit(i)}>
              Edit
            </button>
          </div>
        ))}
      </dl>
    </section>
  );
}
