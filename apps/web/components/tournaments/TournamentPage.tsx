"use client";
// A hosted tournament or league (HostedTournamentScreen): its overview and
// the host's checklist, the teams entered, the schedule, results and news.
// Reads are Firestore listeners; every change goes through the API.
import {
  type CreateTeamResponse,
  divisionLabel,
  effectiveMinRoster,
  entryStatusLabels,
  feeLabel,
  hostedTypeLabels,
  hostedType,
  mixedEntry,
  type SearchPage,
  spotFee,
  takesPlayers,
  takesTeams,
  type EntryDoc,
  type HostedStatus,
} from "@stall10/shared";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { FollowButton } from "@/components/FollowButton";
import { callApi } from "@/lib/client";
import { useRenderZone } from "@/lib/renderZone";
import type { Doc } from "@/lib/live";
import { SignupsSlot } from "./SignupsSlot";
import { DivisionPicker, NoDivisions, ResultsTab, ScheduleTab } from "./TournamentGames";
import { TournamentNews } from "./TournamentNews";
import { JoinToTakePart, PublicNews } from "./VisitorParts";
import { datesLabel, StatusBadge } from "./TournamentLists";
import { type MyTeam, type TournamentState, divisionPath, tournamentPath, useAction, useTournament } from "./useTournament";
import "./tournaments.css";

type Tab = "overview" | "players" | "teams" | "schedule" | "results" | "news";

/** [fallbackHostId] (a group, from ?host=) opens that group's tournament [tournamentId] when no hosted one has the id, as the app does. */
export function TournamentPage({ tournamentId, fallbackHostId }: { tournamentId: string; fallbackHostId?: string }) {
  const s = useTournament(tournamentId);
  const router = useRouter();
  // Only a real id: `..` would otherwise climb out of /teams/.
  const host = fallbackHostId && /^[A-Za-z0-9_-]{1,128}$/.test(fallbackHostId) ? fallbackHostId : undefined;
  const fallback = s.loaded && !s.t && host ? `/teams/${encodeURIComponent(host)}/tournaments/${encodeURIComponent(tournamentId)}` : null;
  useEffect(() => {
    if (fallback) router.replace(fallback);
  }, [fallback, router]);
  useReconcile(s);
  // ?game= (with ?division=) opens on that game, as Report score on a
  // tournament-day card does; ?tab= picks the tab.
  const params = useSearchParams();
  const open = { tab: params.get("tab") ?? undefined, game: params.get("game") ?? undefined, division: params.get("division") ?? undefined };
  if (!s.loaded || fallback) return <p className="muted" aria-busy="true">Loading…</p>;
  if (!s.t) return <p className="empty">This event isn&apos;t here: it may have been removed, or it hasn&apos;t been published yet.</p>;
  return <TournamentView s={s} open={open} />;
}

/**
 * The page itself, for a member's live state or a visitor's read-only one
 * (s.visitor: no Players or News tabs, and a sign-up prompt in place of
 * Follow, entering a team and signing up).
 */
export function TournamentView({ s, open }: { s: TournamentState; open?: { tab?: string; game?: string; division?: string } }) {
  const [tab, setTab] = useState<Tab>(open?.game ? "schedule" : open?.tab === "schedule" || open?.tab === "results" ? open.tab : "overview");
  // The linked division, once the divisions are in.
  const pickedDivision = useRef(false);
  const hasDivision = !!open?.division && s.divisions.some((d) => d.id === open.division);
  useEffect(() => {
    if (pickedDivision.current || !hasDivision || !open?.division) return;
    pickedDivision.current = true;
    s.selectDivision(open.division);
  }, [hasDivision, open?.division, s]);
  const zone = useRenderZone();
  const tournamentId = s.id;
  const t = s.t;
  if (!t) return null;
  const league = t.kind === "league";
  const tabs: Array<[Tab, string]> = [
    ["overview", "Overview"],
    // Who signed up is for members (and only the host sees the list).
    ...(takesPlayers(t) && !s.visitor ? ([["players", "Players"]] as Array<[Tab, string]>) : []),
    ...(takesTeams(t) ? ([["teams", "Teams"]] as Array<[Tab, string]>) : []),
    ["schedule", "Schedule"],
    ["results", league ? "Standings" : "Results"],
    ["news", "News"],
  ];
  const current = tabs.some(([k]) => k === tab) ? tab : "overview";
  return (
    <div className="stack hosted-page">
      <header className="hosted-head">
        <div>
          <small className="muted">
            {hostedTypeLabels[hostedType(t)]} · hosted by <Link href={`/teams/${encodeURIComponent(t.hostId)}`}>{t.hostName}</Link>
          </small>
          <h1>{t.name}</h1>
          <p className="muted">
            {datesLabel(t.startsOn, t.endsOn, zone)}
            {t.location ? ` · ${t.location}` : ""}
          </p>
          <StatusBadge status={t.status} />
        </div>
        <div className="home-actions">
          {t.status !== "draft" && !s.visitor && <FollowButton type="tournament" targetId={tournamentId} groupId={t.hostId} />}
          {s.manager && <ManagerMenu s={s} />}
        </div>
      </header>
      {s.visitor && <JoinToTakePart next={s.visitorNext ?? `/tournaments/${encodeURIComponent(tournamentId)}`} />}
      <nav className="segmented hosted-tabs" aria-label="Sections">
        {tabs.map(([k, label]) => (
          <button key={k} type="button" className={k === current ? "on" : ""} onClick={() => setTab(k)}>
            {label}
          </button>
        ))}
      </nav>
      {current === "overview" && <Overview s={s} />}
      {current === "players" && (
        <SignupsSlot tournamentId={tournamentId} tournament={t} divisions={s.divisions} divisionId={s.divisionId} manager={s.manager} />
      )}
      {current === "teams" && <TeamsTab s={s} />}
      {current === "schedule" && <ScheduleTab s={s} focusGame={open?.game} />}
      {current === "results" && <ResultsTab s={s} />}
      {current === "news" && (s.visitor ? <PublicNews s={s} /> : <TournamentNews s={s} />)}
    </div>
  );
}

/**
 * The app's manager-only background writes (catching up the bracket,
 * going live, recording places and finishing, dropping withdrawn teams,
 * syncing captains): the host's open page asks the API to do whatever is
 * due for the selected division whenever its games or entries change.
 */
function useReconcile(s: TournamentState) {
  const last = useRef("");
  const { user } = s;
  const sig =
    s.manager && s.division && s.t && s.gamesLoaded && s.t.status !== "draft"
      ? JSON.stringify([s.divisionId, s.t.status, s.division.seeds, s.division.captains, s.division.placements, s.games.map((g) => [g.id, g.status, g.scoreA, g.scoreB, g.teamA, g.teamB]), s.entries.map((e) => [e.id, e.status, e.captainIds])])
      : "";
  useEffect(() => {
    if (!sig || !user || sig === last.current) return;
    const timer = setTimeout(() => {
      last.current = sig;
      void callApi(user, `${divisionPath(s.id, s.divisionId ?? "")}/reconcile`, { method: "POST" }).catch(() => {
        last.current = "";
      });
    }, 800);
    return () => clearTimeout(timer);
  }, [sig, user, s.id, s.divisionId]);
}

function ManagerMenu({ s }: { s: TournamentState }) {
  const router = useRouter();
  const { busy, error, run } = useAction();
  async function remove() {
    if (!window.confirm(`Delete ${s.t?.name}? Its divisions, entries, schedule and scores are deleted too. This can't be undone.`)) return;
    const r = await run(tournamentPath(s.id), "DELETE");
    if (r.ok) router.push(`/teams/${encodeURIComponent(s.t?.hostId ?? "")}`);
  }
  return (
    <>
      <Link className="btn btn-small" href={`${`/tournaments/${encodeURIComponent(s.id)}`}/edit`}>
        Edit details
      </Link>
      <button type="button" className="btn btn-small btn-danger" disabled={busy} onClick={() => void remove()}>
        Delete
      </button>
      {error && <p className="form-error">{error}</p>}
    </>
  );
}

const nextSteps: Partial<Record<HostedStatus, Array<{ to: HostedStatus; label: string; hint: string; quiet?: boolean }>>> = {
  draft: [{ to: "registration", label: "Publish and open registration", hint: "Only your managers can see it until you publish." }],
  registration: [{ to: "seeding", label: "Close registration", hint: "Registration is open. Close it when you're ready to seed and schedule." }],
  seeding: [{ to: "registration", label: "Reopen registration", hint: "Registration is closed. Seed the teams, then publish the schedule.", quiet: true }],
};

/** The host's checklist (EventGuide, host side). */
function HostChecklist({ s }: { s: TournamentState }) {
  const { busy, error, run } = useAction();
  const t = s.t;
  if (!t) return null;
  const steps = nextSteps[t.status] ?? [];
  const accepted = s.entriesWith("accepted").length;
  const waiting = s.entriesWith("applied").length;
  return (
    <section className="card">
      <h2 className="card-title">Hosting</h2>
      <ul className="hosted-checklist">
        <li className={s.divisions.length ? "done" : ""}>{s.divisions.length ? `${s.divisions.length} ${s.divisions.length === 1 ? "division" : "divisions"} open` : "Open a division under Edit details"}</li>
        <li className={t.status !== "draft" ? "done" : ""}>{t.status === "draft" ? "Publish it so teams can find it" : "Published"}</li>
        {takesTeams(t) && <li className={accepted >= 2 ? "done" : ""}>{`${accepted} ${accepted === 1 ? "team" : "teams"} accepted${waiting ? `, ${waiting} waiting on you` : ""}`}</li>}
        <li className={s.published ? "done" : ""}>{s.published ? "Schedule published" : "Publish the schedule (Schedule tab)"}</li>
      </ul>
      {steps.map((x) => (
        <div key={x.to} className="stack">
          <small className="muted">{x.hint}</small>
          <div className="home-actions">
            <button type="button" className={`btn btn-small ${x.quiet ? "" : "btn-primary"}`} disabled={busy || (x.to === "registration" && t.status === "draft" && !s.divisions.length)} onClick={() => void run(`${tournamentPath(s.id)}/status`, "PUT", { status: x.to })}>
              {x.label}
            </button>
          </div>
        </div>
      ))}
      {error && <p className="form-error">{error}</p>}
    </section>
  );
}

function Overview({ s }: { s: TournamentState }) {
  const t = s.t!;
  const fee = spotFee(t);
  const zone = useRenderZone();
  const { busy, error, run } = useAction();
  return (
    <div className="stack">
      {s.manager && <HostChecklist s={s} />}
      {!s.manager && !s.visitor && takesTeams(t) && <YourTeams s={s} />}
      {t.description && (
        <section className="card">
          <p className="hosted-description">{t.description}</p>
        </section>
      )}
      <section className="card">
        <h2 className="card-title">Details</h2>
        <dl className="hosted-facts">
          <dt>When</dt>
          <dd>{datesLabel(t.startsOn, t.endsOn, zone)}</dd>
          {t.location && (
            <>
              <dt>Where</dt>
              <dd>{t.location}</dd>
            </>
          )}
          {t.kind === "league" && t.season && (
            <>
              <dt>Season</dt>
              <dd>
                {t.season.weeks} weeks{t.season.playoffTeams ? `, then playoffs for the top ${t.season.playoffTeams}` : ""}
              </dd>
            </>
          )}
          <dt>Who can play</dt>
          <dd>{mixedEntry(t) ? "Players sign up, and teams can reserve a spot" : takesPlayers(t) ? "Players sign up and are drafted onto teams" : t.visibility === "inviteOnly" ? "Teams the host invites" : "Teams apply; the host accepts them"}</dd>
          {t.bidFee && (
            <>
              <dt>{takesPlayers(t) ? "Player fee" : "Team fee"}</dt>
              <dd>{feeLabel(t.bidFee)}{t.bidFee.instructions ? ` · ${t.bidFee.instructions}` : ""}</dd>
            </>
          )}
          {mixedEntry(t) && fee && t.teamFee && (
            <>
              <dt>Team spot fee</dt>
              <dd>{feeLabel(t.teamFee)}</dd>
            </>
          )}
        </dl>
      </section>
      <section className="card">
        <h2 className="card-title">Divisions</h2>
        {s.divisions.length === 0 && <NoDivisions s={s} />}
        <div className="stack">
          {s.divisions.map((d) => {
            const accepted = s.entriesIn(d.id, "accepted").length;
            return (
              <div key={d.id} className="row-card hosted-division-row">
                <div>
                  <b>{divisionLabel(d)}</b>
                  <br />
                  <small className="muted">
                    {takesTeams(t) ? `${accepted} of ${d.maxTeams} teams` : `Up to ${d.maxTeams} teams`} · rosters of {effectiveMinRoster(d)}+
                  </small>
                </div>
                {s.manager && accepted === 0 && d.seeds.length === 0 && (
                  <button
                    type="button"
                    className="text-btn"
                    disabled={busy}
                    onClick={() => {
                      if (window.confirm(`Remove the ${divisionLabel(d)} division?`)) void run(`${divisionPath(s.id, d.id)}`, "DELETE");
                    }}
                  >
                    Remove
                  </button>
                )}
              </div>
            );
          })}
        </div>
        {error && <p className="form-error">{error}</p>}
      </section>
    </div>
  );
}

/** Captain picker: the team's members, as the app's entry sheet offers them. */
function CaptainPicker({ team, value, onChange }: { team: MyTeam | undefined; value: string[]; onChange: (v: string[]) => void }) {
  const names = Object.entries(team?.memberNames ?? {}).sort((a, b) => a[1].localeCompare(b[1]));
  if (!names.length) return <p className="muted small">The team&apos;s members show up here to pick captains.</p>;
  return (
    <fieldset className="hosted-captains">
      <legend>Captains (they report scores; up to 4)</legend>
      {names.map(([uid, name]) => (
        <label key={uid} className="switch-row">
          <input
            type="checkbox"
            checked={value.includes(uid)}
            onChange={(e) => onChange(e.target.checked ? [...value, uid].slice(0, 4) : value.filter((x) => x !== uid))}
          />
          {name}
        </label>
      ))}
    </fieldset>
  );
}

/** Apply, accept an invite or change captains for one of the viewer's teams. */
function EntryForm({ s, team, entry, onDone }: { s: TournamentState; team: MyTeam | undefined; entry: Doc<EntryDoc> | null; onDone?: () => void }) {
  const [div, setDiv] = useState(entry?.divisionId ?? s.divisions[0]?.id ?? "");
  const [captains, setCaptains] = useState<string[]>(entry?.captainIds ?? (s.uid ? [s.uid] : []));
  const { busy, error, run } = useAction();
  if (!team) return null;
  const label = entry?.status === "invited" ? "Accept the invite" : entry && entry.status !== "withdrawn" ? "Save captains" : "Apply";
  return (
    <form
      className="settings-form"
      onSubmit={async (e) => {
        e.preventDefault();
        const r = await run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(team.id)}`, "PUT", { divisionId: div, captainIds: captains });
        if (r.ok) onDone?.();
      }}
    >
      {(!entry || entry.status === "withdrawn") && s.divisions.length > 1 && (
        <label>
          Division
          <select value={div} onChange={(e) => setDiv(e.target.value)}>
            {s.divisions.map((d) => (
              <option key={d.id} value={d.id}>
                {divisionLabel(d)}
              </option>
            ))}
          </select>
        </label>
      )}
      <CaptainPicker team={team} value={captains} onChange={setCaptains} />
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions">
        <button className="btn btn-primary btn-small" disabled={busy || !div || captains.length === 0}>
          {label}
        </button>
        {onDone && (
          <button type="button" className="text-btn" onClick={onDone}>
            Cancel
          </button>
        )}
      </div>
    </form>
  );
}

/** "Your teams" (EventGuide, team side): entries of teams the viewer runs. */
function YourTeams({ s }: { s: TournamentState }) {
  const t = s.t!;
  const [applying, setApplying] = useState<string>("");
  const [editing, setEditing] = useState<string | null>(null);
  const { busy, error, run } = useAction();
  const open = t.status === "registration";
  const canApply = open && t.visibility === "public" && s.divisions.length > 0;
  if (!s.myEntries.length && !s.myAdminTeams.length && !(mixedEntry(t) && open)) return null;
  return (
    <section className="card">
      <h2 className="card-title">Your teams</h2>
      <div className="stack">
        {s.myEntries
          .filter((e) => e.status !== "withdrawn")
          .map((e) => {
            const team = s.myAdminTeams.find((m) => m.id === e.id);
            const d = s.divisions.find((x) => x.id === e.divisionId);
            return (
              <div key={e.id} className="row-card hosted-entry">
                <div>
                  <b>{e.teamName}</b> <span className="pill">{entryStatusLabels[e.status]}</span>
                  <br />
                  <small className="muted">
                    {d ? divisionLabel(d) : ""} · captains: {e.captainIds.map((c) => team?.memberNames?.[c] ?? "a member").join(", ")}
                  </small>
                </div>
                {editing === e.id || e.status === "invited" ? (
                  <EntryForm s={s} team={team} entry={e} onDone={e.status === "invited" ? undefined : () => setEditing(null)} />
                ) : (
                  e.status !== "declined" && (
                    <div className="home-actions">
                      <button type="button" className="text-btn" onClick={() => setEditing(e.id)}>
                        Captains
                      </button>
                      <button
                        type="button"
                        className="text-btn"
                        disabled={busy}
                        onClick={() => {
                          if (window.confirm(`Withdraw ${e.teamName}?`)) void run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(e.id)}/status`, "PUT", { status: "withdrawn" });
                        }}
                      >
                        Withdraw
                      </button>
                    </div>
                  )
                )}
              </div>
            );
          })}
        {canApply && s.teamsToEnter.length > 0 && !s.myActiveEntry && (
          <div className="stack">
            <label>
              Enter a team
              <select value={applying} onChange={(e) => setApplying(e.target.value)}>
                <option value="">Pick one of your teams</option>
                {s.teamsToEnter.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.name}
                  </option>
                ))}
              </select>
            </label>
            {applying && <EntryForm key={applying} s={s} team={s.teamsToEnter.find((m) => m.id === applying)} entry={s.entryOf(applying)} onDone={() => setApplying("")} />}
          </div>
        )}
        {mixedEntry(t) && open && t.visibility === "public" && s.divisions.length > 0 && !s.myActiveEntry && <ReserveSpot s={s} />}
        {!open && !s.myEntries.length && <p className="muted">Registration isn&apos;t open.</p>}
      </div>
      {error && <p className="form-error">{error}</p>}
    </section>
  );
}

/** Start a team for this event and reserve it a spot (canReserve). */
function ReserveSpot({ s }: { s: TournamentState }) {
  const [name, setName] = useState("");
  const [div, setDiv] = useState(s.divisions[0]?.id ?? "");
  const { busy, error, setError, run } = useAction();
  const fee = s.t ? spotFee(s.t) : null;
  return (
    <form
      className="settings-form"
      onSubmit={async (e) => {
        e.preventDefault();
        const d = s.divisions.find((x) => x.id === div);
        if (!d || !s.uid) return setError("Pick a division.");
        if (!name.trim()) return setError("Name your team.");
        const made = await run<CreateTeamResponse>("/v1/teams", "POST", { name: name.trim(), division: d.division, level: d.level, leagueId: s.id });
        if (!made.ok) return;
        await run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(made.value.id)}`, "PUT", { divisionId: d.id, captainIds: [s.uid] });
      }}
    >
      <b>Or reserve a spot for your team{fee ? ` · ${feeLabel(fee)}` : ""}</b>
      <div className="form-grid">
        <label>
          Team name
          <input value={name} maxLength={60} onChange={(e) => setName(e.target.value)} />
        </label>
        {s.divisions.length > 1 && (
          <label>
            Division
            <select value={div} onChange={(e) => setDiv(e.target.value)}>
              {s.divisions.map((d) => (
                <option key={d.id} value={d.id}>
                  {divisionLabel(d)}
                </option>
              ))}
            </select>
          </label>
        )}
      </div>
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions">
        <button className="btn btn-primary btn-small" disabled={busy}>
          Start a team and reserve a spot
        </button>
      </div>
    </form>
  );
}

/** The Teams tab: seeds, entries waiting on the host, inviting teams. */
function TeamsTab({ s }: { s: TournamentState }) {
  const d = s.division;
  const { busy, error, run } = useAction();
  if (!d || !s.t) return <NoDivisions s={s} />;
  const seedable = s.manager && !s.published;
  const move = (i: number, by: number) => {
    const seeds = [...d.seeds];
    const [x] = seeds.splice(i, 1);
    seeds.splice(i + by, 0, x);
    void run(`${divisionPath(s.id, d.id)}/seeds`, "PUT", { seeds });
  };
  const decide = (teamId: string, status: string) => void run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(teamId)}/status`, "PUT", { status });
  const waiting = s.entriesIn(d.id).filter((e) => e.status === "applied" || e.status === "waitlisted");
  const others = s.entriesIn(d.id).filter((e) => e.status === "invited" || e.status === "declined" || e.status === "withdrawn");
  return (
    <div className="stack">
      <DivisionPicker s={s} />
      {!s.manager && !s.visitor && <YourTeams s={s} />}
      <section className="card">
        <h2 className="card-title">
          {d.seeds.length} of {d.maxTeams} teams
        </h2>
        {d.seeds.length === 0 && <p className="muted">No teams accepted yet.</p>}
        <ol className="hosted-seeds">
          {d.seeds.map((id, i) => (
            <li key={id} className="row-card">
              <span>
                <b>{i + 1}</b> {s.teamName(id)}
              </span>
              {seedable && (
                <span className="home-actions">
                  <button type="button" className="text-btn" aria-label="Move up" disabled={busy || i === 0} onClick={() => move(i, -1)}>
                    ↑
                  </button>
                  <button type="button" className="text-btn" aria-label="Move down" disabled={busy || i === d.seeds.length - 1} onClick={() => move(i, 1)}>
                    ↓
                  </button>
                  {s.entryOf(id) && (
                    <button type="button" className="text-btn" disabled={busy} onClick={() => window.confirm(`Withdraw ${s.teamName(id)}?`) && decide(id, "withdrawn")}>
                      Withdraw
                    </button>
                  )}
                </span>
              )}
            </li>
          ))}
        </ol>
        {s.manager && s.published && <small className="muted">Seeds are locked once the schedule is published.</small>}
      </section>
      {s.manager && waiting.length > 0 && (
        <section className="card">
          <h2 className="card-title">Waiting on you</h2>
          <div className="stack">
            {waiting.map((e) => (
              <div key={e.id} className="row-card">
                <span>
                  <b>{e.teamName}</b> <span className="pill">{entryStatusLabels[e.status]}</span>
                </span>
                <span className="home-actions">
                  <button type="button" className="btn btn-primary btn-small" disabled={busy || d.seeds.length >= d.maxTeams} onClick={() => decide(e.id, "accepted")}>
                    Accept
                  </button>
                  {e.status !== "waitlisted" && (
                    <button type="button" className="btn btn-small" disabled={busy} onClick={() => decide(e.id, "waitlisted")}>
                      Waitlist
                    </button>
                  )}
                  <button type="button" className="text-btn" disabled={busy} onClick={() => decide(e.id, "declined")}>
                    Decline
                  </button>
                </span>
              </div>
            ))}
          </div>
        </section>
      )}
      {s.manager && others.length > 0 && (
        <section className="card">
          <h2 className="card-title">Invited and others</h2>
          {others.map((e) => (
            <div key={e.id} className="row-card">
              <span>{e.teamName}</span>
              <span className="pill">{entryStatusLabels[e.status]}</span>
            </div>
          ))}
        </section>
      )}
      {s.manager && ["draft", "registration", "seeding"].includes(s.t.status) && <InviteTeams s={s} divisionId={d.id} />}
      {error && <p className="form-error">{error}</p>}
    </div>
  );
}

function InviteTeams({ s, divisionId }: { s: TournamentState; divisionId: string }) {
  const [q, setQ] = useState("");
  const [results, setResults] = useState<SearchPage["teams"] | null>(null);
  const { busy, error, run } = useAction();
  const { user } = s;
  useEffect(() => {
    const term = q.trim();
    if (!user || term.length < 2) {
      setResults(null);
      return;
    }
    let live = true;
    const timer = setTimeout(() => {
      callApi<SearchPage>(user, `/v1/public/search?q=${encodeURIComponent(term)}`)
        .then((page) => live && setResults(page.teams.filter((x) => (x.kind ?? "team") === "team")))
        .catch(() => live && setResults([]));
    }, 300);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [q, user]);
  return (
    <section className="card">
      <h2 className="card-title">Invite a team</h2>
      <input type="search" placeholder="Search teams" value={q} onChange={(e) => setQ(e.target.value)} />
      <div className="stack">
        {results?.length === 0 && <p className="muted">No teams found.</p>}
        {results?.map((x) => {
          const e = s.entryOf(x.id);
          const taken = !!e && e.status !== "withdrawn";
          return (
            <div key={x.id} className="row-card">
              <span>
                {x.name}
                {x.city ? <small className="muted"> · {x.city}</small> : null}
              </span>
              {taken ? (
                <span className="pill">{entryStatusLabels[e.status]}</span>
              ) : (
                <button type="button" className="btn btn-small" disabled={busy} onClick={() => void run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(x.id)}/invite`, "POST", { divisionId })}>
                  Invite
                </button>
              )}
            </div>
          );
        })}
      </div>
      {error && <p className="form-error">{error}</p>}
    </section>
  );
}
