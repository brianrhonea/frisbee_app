"use client";
// Entering a team on a page of its own, /tournaments/:id/enter (the app's
// full-screen EnterTeamScreen): "Apply to play" picks one of the viewer's
// teams, its division and captains; ?team= with an invite is "Accept the
// invite" (division and captains); ?team= with an entry already in is
// "Captains". Every rule is the API's (PUT .../entries/:teamId); this page
// only offers what the event page would.
import { divisionLabel, type EntryDoc } from "@stall10/shared";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import type { Doc } from "@/lib/live";
import { TeamMark } from "./TournamentGames";
import { type MyTeam, type TournamentState, tournamentPath, useAction, useTournament } from "./useTournament";
import "./tournaments.css";

const maxCaptains = 4;

type Mode = "apply" | "invite" | "captains";

export function EnterTeam({ tournamentId, teamId }: { tournamentId: string; teamId?: string }) {
  const s = useTournament(tournamentId);
  if (!s.loaded || (s.t && !s.divisions.length && s.t.divisions.length > 0)) return <p className="muted" aria-busy="true">Loading…</p>;
  if (!s.t) return <p className="empty">This event isn&apos;t here: it may have been removed, or it hasn&apos;t been published yet.</p>;
  const back = `/tournaments/${encodeURIComponent(tournamentId)}`;
  const entry = teamId ? s.entryOf(teamId) : null;
  const team = teamId ? s.myAdminTeams.find((m) => m.id === teamId) : undefined;
  const mode: Mode = entry?.status === "invited" ? "invite" : entry && !["withdrawn", "declined"].includes(entry.status) ? "captains" : "apply";
  const t = s.t;
  const why =
    mode === "apply"
      ? t.status !== "registration"
        ? "Registration isn't open."
        : t.visibility !== "public"
          ? "Teams play here by the host's invitation."
          : s.divisions.length === 0
            ? "The host is still setting up divisions."
            : s.myActiveEntry
              ? `${s.myActiveEntry.teamName} is already entered here.`
              : s.teamsToEnter.length === 0
                ? "None of the teams you run can enter: you need to be an owner or admin of a team that hasn't entered."
                : null
      : !team
        ? "Only the team's admins can change its entry."
        : null;
  return (
    <div className="stack hosted-page enter-team">
      <header className="bracket-page-head">
        <small className="muted">
          <Link href={back}>← {t.name}</Link>
        </small>
        <h1>{mode === "captains" ? "Captains" : mode === "invite" ? "Accept the invite" : "Apply to play"}</h1>
      </header>
      {why ? (
        <p className="empty">{why}</p>
      ) : (
        <EntryForm key={`${mode}:${teamId ?? ""}`} s={s} mode={mode} entry={entry} fixedTeam={mode === "apply" ? undefined : team} preselect={teamId} back={back} />
      )}
    </div>
  );
}

function EntryForm({
  s,
  mode,
  entry,
  fixedTeam,
  preselect,
  back,
}: {
  s: TournamentState;
  mode: Mode;
  entry: Doc<EntryDoc> | null;
  fixedTeam: MyTeam | undefined;
  preselect?: string;
  back: string;
}) {
  const router = useRouter();
  const choices = fixedTeam ? [fixedTeam] : s.teamsToEnter;
  const [teamId, setTeamId] = useState(choices.find((m) => m.id === preselect)?.id ?? choices[0]?.id ?? "");
  const team = choices.find((m) => m.id === teamId);
  // The division matching the team's own, if there is one.
  const matching = (m: MyTeam | undefined) => s.divisions.find((d) => m && d.division === m.division && d.level === m.level)?.id ?? s.divisions[0]?.id ?? "";
  const [div, setDiv] = useState(entry?.divisionId ?? matching(team));
  const [captains, setCaptains] = useState<string[]>(entry && mode === "captains" ? entry.captainIds : s.uid ? [s.uid] : []);
  const { busy, error, run } = useAction();
  const names = Object.entries(team?.memberNames ?? {}).sort((a, b) => a[1].localeCompare(b[1]));
  const label = mode === "captains" ? "Save" : mode === "invite" ? "Accept" : "Apply";
  return (
    <form
      className="stack"
      onSubmit={async (e) => {
        e.preventDefault();
        if (!team) return;
        const r = await run(`${tournamentPath(s.id)}/entries/${encodeURIComponent(team.id)}`, "PUT", { divisionId: div, captainIds: captains });
        if (r.ok) router.push(back);
      }}
    >
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
                    {Object.keys(m.memberNames ?? {}).length} {Object.keys(m.memberNames ?? {}).length === 1 ? "player" : "players"}
                  </small>
                </span>
              </label>
            ))}
          </div>
        )}
      </section>
      {mode !== "captains" && (
        <section className="card settings-form">
          <h2 className="card-title">Division</h2>
          <div className="segmented hosted-divisions" role="group" aria-label="Division">
            {s.divisions.map((d) => {
              const full = s.entriesIn(d.id, "accepted").length >= d.maxTeams;
              return (
                <button key={d.id} type="button" className={d.id === div ? "on" : ""} aria-pressed={d.id === div} disabled={mode === "invite" && d.id !== div} onClick={() => setDiv(d.id)}>
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
          {label}
        </button>
        <Link className="btn btn-quiet" href={back}>
          Cancel
        </Link>
      </div>
    </form>
  );
}
