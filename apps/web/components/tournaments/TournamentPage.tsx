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
  inviteExpired,
  inviteExpiredMessage,
  mixedEntry,
  type SearchPage,
  spotFee,
  takesPlayers,
  takesTeams,
  type HostedStatus,
} from "@stall10/shared";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { FollowButton } from "@/components/FollowButton";
import { LocalTime } from "@/components/LocalTime";
import { ShareButton, tournamentUrl } from "@/components/ShareButton";
import { usePayments } from "@/components/drafts/data";
import { HostPaymentControls, PayOnline, PayoutsCard } from "@/components/payments/Payments";
import { inChats, OrganizerChats, TeamChatButton } from "./TournamentChats";
import { callApi } from "@/lib/client";
import { dayKey, useRenderZone } from "@/lib/renderZone";
import { SignupsSlot } from "./SignupsSlot";
import { DivisionPicker, NoDivisions, ResultsTab, ScheduleTab, TeamMark } from "./TournamentGames";
import { TournamentNews } from "./TournamentNews";
import { JoinToTakePart, PublicNews } from "./VisitorParts";
import { datesLabel, StatusBadge } from "./TournamentLists";
import { type TournamentState, divisionPath, tournamentPath, useAction, useTournament } from "./useTournament";
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
  // A game to open or an asked-for tab first; on a live event the
  // schedule with the viewer's games (startTab in the app).
  const [tab, setTab] = useState<Tab>(open?.game ? "schedule" : open?.tab === "schedule" || open?.tab === "results" ? open.tab : s.t?.status === "live" ? "schedule" : "overview");
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
  const board = boardStatus(t, zone);
  const host = (
    <>
      {hostedTypeLabels[hostedType(t)]} · hosted by <Link href={`/teams/${encodeURIComponent(t.hostId)}`}>{t.hostName}</Link>
    </>
  );
  const where = `${datesLabel(t.startsOn, t.endsOn, zone)}${t.location ? ` · ${t.location}` : ""}`;
  return (
    <div className="stack hosted-page">
      <header className={`hosted-head${board ? " hosted-board" : ""}`}>
        <div className="hosted-head-main">
          {board ? (
            <div className="hosted-head-tags">
              {t.status === "live" ? (
                <span className="hosted-live-pill">
                  <i aria-hidden />
                  {board}
                </span>
              ) : (
                <span className="hosted-today-pill">{board}</span>
              )}
              <small className="hosted-eyebrow">{host}</small>
            </div>
          ) : (
            <div className="hosted-head-tags">
              <StatusBadge status={t.status} />
              <small className="muted">{host}</small>
            </div>
          )}
          <h1>{t.name}</h1>
          <p className="hosted-meta">{where}</p>
          {board && <LiveHeadline s={s} />}
        </div>
        <div className="home-actions hosted-head-actions">
          {t.status !== "draft" && !s.visitor && <FollowButton type="tournament" targetId={tournamentId} groupId={t.hostId} />}
          {/* A draft has no public page to link to yet. */}
          {t.status !== "draft" && <ShareButton url={tournamentUrl(tournamentId)} title={`${t.name} on Stall 10`} className="btn btn-small btn-quiet" />}
          {s.manager && <ManagerMenu s={s} />}
        </div>
      </header>
      {s.visitor && <JoinToTakePart next={s.visitorNext ?? `/tournaments/${encodeURIComponent(tournamentId)}`} />}
      <nav className="hosted-tabs" aria-label="Sections">
        {tabs.map(([k, label]) => (
          <button key={k} type="button" className={k === current ? "on" : ""} aria-pressed={k === current} onClick={() => setTab(k)}>
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
 * The game being played, on the navy header: "nameA 7–5 nameB · +2 more
 * live", the viewer's own game first, else the first on the schedule;
 * nothing when none is live.
 */
function LiveHeadline({ s }: { s: TournamentState }) {
  const live = s.liveGames;
  if (live.length === 0) return null;
  const g = live.find((x) => s.myTeamIds.has(x.teamA ?? "") || s.myTeamIds.has(x.teamB ?? "")) ?? live[0];
  const l = s.liveOf(g);
  if (!l) return null;
  return (
    <p className="hosted-live-line">
      <i aria-hidden />
      <span>
        <b>{s.teamName(g.teamA)}</b> <span className="hosted-live-score">{l.scoreA}–{l.scoreB}</span> <b>{s.teamName(g.teamB)}</b>
        {live.length > 1 && <span className="hosted-live-more"> · +{live.length - 1} more live</span>}
      </span>
    </p>
  );
}

/**
 * What the scoreboard-navy header says, or null for the plain one (onBoard
 * in the app): "Live" while it's live, "Today" on a scheduled event's days,
 * with "· Week 3 of 8" in a league's season. Days are in [zone]
 * (useRenderZone), so the server's HTML and the first render agree.
 */
function boardStatus(t: NonNullable<TournamentState["t"]>, zone: string | undefined): string | null {
  if (!t.startsOn || (t.status !== "live" && t.status !== "scheduled")) return t.status === "live" ? "Live" : null;
  const today = dayKey(new Date(), zone);
  const start = dayKey(new Date(t.startsOn), zone);
  const end = dayKey(new Date(t.endsOn ?? t.startsOn), zone);
  if (t.status !== "live" && (today < start || today > end)) return null;
  const label = t.status === "live" ? "Live" : "Today";
  const weeks = t.kind === "league" ? t.season?.weeks : undefined;
  if (!weeks) return label;
  const days = Math.round((Date.parse(`${today}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000);
  return `${label} · Week ${Math.min(Math.max(Math.floor(days / 7) + 1, 1), weeks)} of ${weeks}`;
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
      <button type="button" className="btn btn-small" disabled={busy} onClick={() => void remove()}>
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

/**
 * The host's checklist (HostChecklist in the app): "Next steps", how many
 * are done, then each step ticked when done and the first one left in
 * amber (the host's to do), then the status button for where it's at.
 */
function HostChecklist({ s }: { s: TournamentState }) {
  const { busy, error, run } = useAction();
  const t = s.t;
  if (!t) return null;
  const steps = nextSteps[t.status] ?? [];
  const accepted = s.entriesWith("accepted").length;
  const waiting = s.entriesWith("applied").length;
  const items: Array<{ done: boolean; label: string }> = [
    { done: s.divisions.length > 0, label: s.divisions.length ? `${s.divisions.length} ${s.divisions.length === 1 ? "division" : "divisions"} open` : "Open a division under Edit details" },
    { done: t.status !== "draft", label: t.status === "draft" ? "Publish it so teams can find it" : "Published" },
    ...(takesTeams(t) ? [{ done: accepted >= 2, label: `${accepted} ${accepted === 1 ? "team" : "teams"} accepted${waiting ? `, ${waiting} waiting on you` : ""}` }] : []),
    { done: s.published, label: s.published ? "Schedule published" : "Publish the schedule (Schedule tab)" },
  ];
  const done = items.filter((x) => x.done).length;
  const current = items.findIndex((x) => !x.done);
  return (
    <section className="card hosted-steps">
      <div className="card-head">
        <h2 className="card-title">Next steps</h2>
        <small className="muted">
          {done} of {items.length} done
        </small>
      </div>
      <div className="hosted-steps-bar" aria-hidden>
        <i style={{ width: `${(done / items.length) * 100}%` }} />
      </div>
      <ol className="hosted-checklist">
        {items.map((x, i) => (
          <li key={i} className={x.done ? "done" : i === current ? "current" : ""}>
            <span className="hosted-step-mark" aria-hidden>
              {x.done ? "✓" : i + 1}
            </span>
            <span>
              {x.label}
              {x.done && <span className="sr-only"> (done)</span>}
            </span>
          </li>
        ))}
      </ol>
      {steps.map((x) => (
        <div key={x.to} className="stack hosted-step-action">
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
      {/* The host's owner connects Stripe here (hidden for others). */}
      {s.manager && s.user && (fee || (t.entryType === "players" && t.bidFee)) && <PayoutsCard user={s.user} teamId={t.hostId} amountCents={(fee ?? t.bidFee)?.amountCents} />}
      {/* An organizer who also runs a team sees its entry and fee too. */}
      {!s.visitor && takesTeams(t) && <YourTeams s={s} />}
      {/* Captains ask the organizers; organizers answer everyone at once. */}
      {!s.visitor && takesTeams(t) && <OrganizerChats s={s} />}
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

/** Entering a team, accepting an invite or changing captains ([teamId]) happens on its own page (EnterTeam). */
const enterHref = (tournamentId: string, teamId?: string) =>
  `/tournaments/${encodeURIComponent(tournamentId)}/enter${teamId ? `?team=${encodeURIComponent(teamId)}` : ""}`;

/**
 * An invite's answer: its reply-by time and Accept (the enter page, to
 * pick captains) / Decline, or Expired once that time has passed.
 */
export function InviteAnswer({ entry, href, busy, onDecline }: { entry: { status: string; replyBy?: string | null }; href: string; busy: boolean; onDecline: () => void }) {
  if (inviteExpired(entry, new Date())) {
    return (
      <div className="stack">
        <span className="pill">Expired</span>
        <small className="muted">{inviteExpiredMessage}</small>
      </div>
    );
  }
  return (
    <div className="stack">
      {entry.replyBy && (
        <small className="muted">
          Reply by <LocalTime iso={entry.replyBy} />
        </small>
      )}
      <div className="home-actions">
        <Link className="btn btn-primary btn-small" href={href}>
          Accept
        </Link>
        <button type="button" className="btn btn-small" disabled={busy} onClick={onDecline}>
          Decline
        </button>
      </div>
    </div>
  );
}

/** "Your teams" (EventGuide, team side): entries of teams the viewer runs. */
function YourTeams({ s }: { s: TournamentState }) {
  const t = s.t!;
  const { busy, error, run } = useAction();
  const open = t.status === "registration";
  const canApply = open && t.visibility === "public" && s.divisions.length > 0;
  const fee = spotFee(t);
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
                  {fee && s.user && ["applied", "accepted", "waitlisted"].includes(e.status) && (
                    <PayOnline user={s.user} tournamentId={s.id} teamId={e.id} withStatus />
                  )}
                </div>
                {e.status === "invited" ? (
                  <InviteAnswer
                    entry={e}
                    href={enterHref(s.id, e.id)}
                    busy={busy}
                    onDecline={() => {
                      if (window.confirm(`Decline the invite for ${e.teamName}?`)) void run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(e.id)}/status`, "PUT", { status: "withdrawn" });
                    }}
                  />
                ) : (
                  e.status !== "declined" && (
                    <div className="home-actions">
                      <Link className="text-btn" href={enterHref(s.id, e.id)}>
                        Captains
                      </Link>
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
          <div className="home-actions">
            <Link className="btn btn-primary btn-small" href={enterHref(s.id)}>
              Enter a team
            </Link>
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
  // The host marks each team's bid or spot fee here, as in the app.
  const payments = usePayments(s.id, s.manager).data ?? [];
  if (!d || !s.t) return <NoDivisions s={s} />;
  const fee = spotFee(s.t);
  const paymentById = new Map(payments.map((x) => [x.id, x]));
  // Drafted teams' players pay one by one, not as a team.
  const owes = (id: string) => !!fee && fee.amountCents > 0 && !(d.teams ?? []).some((x) => x.id === id);
  const overdue = (id: string) => !!fee?.dueAt && Date.now() > Date.parse(fee.dueAt) && paymentById.get(id)?.paid !== true;
  const seedable = s.manager && !s.published;
  const move = (i: number, by: number) => {
    const seeds = [...d.seeds];
    const [x] = seeds.splice(i, 1);
    seeds.splice(i + by, 0, x);
    void run(`${divisionPath(s.id, d.id)}/seeds`, "PUT", { seeds });
  };
  const decide = (teamId: string, status: string) => void run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(teamId)}/status`, "PUT", { status });
  const waiting = s.entriesIn(d.id).filter((e) => e.status === "applied" || e.status === "waitlisted");
  const applied = waiting.filter((e) => e.status === "applied").length;
  const others = s.entriesIn(d.id).filter((e) => e.status === "invited" || e.status === "declined" || e.status === "withdrawn");
  return (
    <div className="stack">
      <DivisionPicker s={s} />
      {!s.visitor && <YourTeams s={s} />}
      <div className="hosted-stats">
        <div className="hosted-stat">
          <b>
            {d.seeds.length}
            <small>/{d.maxTeams}</small>
          </b>
          <span>Accepted</span>
        </div>
        {/* A visitor's public page has only the accepted teams. */}
        {!s.visitor && (
          <>
            <div className="hosted-stat">
              <b>{waiting.length - applied}</b>
              <span>Waitlist</span>
            </div>
            <div className={`hosted-stat${s.manager && applied > 0 ? " hosted-stat-due" : ""}`}>
              <b>{applied}</b>
              <span>Applied</span>
            </div>
          </>
        )}
      </div>
      {s.manager && waiting.length > 0 && (
        <section className="card">
          <div className="card-head">
            <h2 className="card-title">Waiting</h2>
            {applied > 0 && <small className="hosted-due-note">Waiting on you</small>}
          </div>
          <div className="stack">
            {waiting.map((e) => (
              <div key={e.id} className={`row-card${e.status === "applied" ? " hosted-row-due" : ""}`}>
                <span>
                  <b>{e.teamName}</b> <span className={`pill ${e.status === "applied" ? "hosted-pill-due" : "pill-soft"}`}>{entryStatusLabels[e.status]}</span>
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
                  {s.user && s.t?.status !== "draft" && <TeamChatButton user={s.user} tournamentId={s.id} teamId={e.id} teamName={e.teamName} />}
                </span>
              </div>
            ))}
          </div>
        </section>
      )}
      <section className="card">
        <h2 className="card-title">
          {d.seeds.length} of {d.maxTeams} teams
        </h2>
        {d.seeds.length === 0 && <p className="muted">{s.manager ? "No teams yet. Accept applications above or invite teams." : "No teams accepted yet."}</p>}
        <ol className="hosted-seeds">
          {d.seeds.map((id, i) => (
            <li key={id} className="row-card">
              <span className="hosted-seed">
                <b className="hosted-seed-n">{i + 1}</b>
                <TeamMark name={s.teamName(id)} />
                <span>{s.teamName(id)}</span>
              </span>
              {s.manager && s.user && owes(id) && <HostPaymentControls user={s.user} tournamentId={s.id} payerId={id} payment={paymentById.get(id)} overdue={overdue(id)} />}
              {s.manager && s.user && s.t?.status !== "draft" && inChats(s.entries.find((e) => e.id === id)) && <TeamChatButton user={s.user} tournamentId={s.id} teamId={id} teamName={s.teamName(id)} />}
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
      {s.manager && others.length > 0 && (
        <section className="card">
          <h2 className="card-title">Invited and others</h2>
          {others.map((e) => {
            const expired = inviteExpired(e, new Date());
            return (
              <div key={e.id} className="row-card">
                <span>
                  {e.teamName}
                  {e.status === "invited" && e.replyBy && !expired && (
                    <>
                      <br />
                      <small className="muted">
                        Reply by <LocalTime iso={e.replyBy} />
                      </small>
                    </>
                  )}
                </span>
                <span className="home-actions">
                  <span className="pill">{expired ? "Expired" : entryStatusLabels[e.status]}</span>
                  {expired && ["draft", "registration", "seeding"].includes(s.t!.status) && (
                    <button type="button" className="btn btn-small" disabled={busy} onClick={() => void run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(e.id)}/invite`, "POST", { divisionId: e.divisionId })}>
                      Invite again
                    </button>
                  )}
                </span>
              </div>
            );
          })}
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
