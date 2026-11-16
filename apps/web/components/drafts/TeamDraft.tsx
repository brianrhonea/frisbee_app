"use client";
import "./drafts.css";
import {
  balancedDraft,
  blankTeams,
  type DraftedTeam,
  draftedTeamsProblem,
  genderMatchLabels,
  movePlayer,
  registeredSeeds,
  signupOrder,
  suggestedTeamCount,
  teamsCreated,
} from "@stall10/shared";
import type { User } from "firebase/auth";
import { useEffect, useState } from "react";
import type { Doc } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { attempt, type DivisionDoc, divisionLabel, draftApi, type TournamentDoc, teamsOf, useHasGames, useSignups, useTournamentBase } from "./data";

/**
 * The host turns a division's accepted players into teams (the app's
 * TeamDraftScreen): deal balanced teams from skill and gender match, then
 * move players, rename teams and pick captains before saving. After a
 * captains' draft it adjusts the captains' teams instead of dealing.
 */
export function TeamDraft({ tournamentId, divisionId }: { tournamentId: string; divisionId: string }) {
  const { user } = useAuth();
  const uid = user?.uid ?? null;
  const { tournament, divisions, manager, managerKnown } = useTournamentBase(tournamentId, uid);
  if (!user) return null;
  if (!managerKnown || tournament.data === undefined || divisions.data === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
  const division = divisions.data.find((d) => d.id === divisionId);
  if (!tournament.data || !division) return <div className="empty">Division not found. It may have been removed.</div>;
  if (!manager) return <div className="empty">Only the event&apos;s organizers can draft teams.</div>;
  return <Editor user={user} tournamentId={tournamentId} tournament={tournament.data} division={division} />;
}

function Editor({ user, tournamentId, tournament, division: d }: { user: User; tournamentId: string; tournament: TournamentDoc; division: Doc<DivisionDoc> }) {
  const signups = useSignups(tournamentId, true).data ?? [];
  const locked = useHasGames(tournamentId, d.id) === true;
  const saved = teamsOf(d);
  const [teams, setTeams] = useState<DraftedTeam[] | null>(null);
  const [count, setCount] = useState<number | null>(null);
  const [seed, setSeed] = useState(() => Date.now() & 0xffff);
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // Start from the saved teams until the host edits.
  useEffect(() => {
    if (!dirty) setTeams(null);
  }, [dirty, d.teams]);
  const current = teams ?? saved;
  const created = teamsCreated(saved);
  const mixed = d.division === "mixed";
  const fromCaptains = tournament.draftMode === "captains" && saved.length > 0;
  // In the app's order (by name), which the balanced draft deals from.
  const players = signups.filter((s) => s.divisionId === d.id && s.status === "accepted").sort(signupOrder);
  const accepted = new Set(players.map((p) => p.id));
  const placed = new Set(current.flatMap((t) => t.playerIds));
  const unassigned = players.filter((p) => !placed.has(p.id)).sort((a, b) => a.name.localeCompare(b.name));
  const stale = current.flatMap((t) => t.playerIds.filter((id) => !accepted.has(id)));
  const signupOf = (id: string) => players.find((p) => p.id === id) ?? signups.find((s) => s.id === id);
  const skillOf = (t: DraftedTeam) => t.playerIds.reduce((n, id) => n + (signupOf(id)?.skill ?? 0), 0);
  const reg = registeredSeeds(d).length;
  const maxTeams = Math.max(2, (d.maxTeams ?? 16) - reg);
  const teamCount = count ?? (current.length > 0 ? current.length : suggestedTeamCount(players.length, d.settings?.playersOnField ?? 5, maxTeams));

  function set(next: DraftedTeam[]) {
    if (created) return;
    setTeams(next);
    setDirty(true);
    setNotice(null);
  }

  function setTeamCount(n: number) {
    if (locked || created) return;
    const c = Math.min(Math.max(n, 2), maxTeams);
    setCount(c);
    if (c > current.length) set([...current, ...blankTeams(c - current.length, current)]);
    else if (c < current.length) set(current.slice(0, c));
  }

  function deal(nextSeed: number) {
    setError(null);
    if (fromCaptains) return setError("The captains drafted these teams. Adjust them instead.");
    if (created) return setError("The league's teams are made. Manage rosters on each team.");
    if (locked) return setError("The schedule is published, so teams can only be adjusted.");
    if (players.length < 2) return setError("Accept at least two players first.");
    const base = current.length === teamCount ? current : [...current.slice(0, teamCount), ...(teamCount > current.length ? blankTeams(teamCount - current.length, current) : [])];
    setCount(teamCount);
    set(balancedDraft(players.map((p) => ({ uid: p.id, name: p.name, skill: p.skill, gender: p.gender ?? null })), base, { seed: nextSeed, mixed }));
  }

  function move(id: string, teamId: string | null) {
    const name = signupOf(id)?.name ?? current.map((t) => t.playerNames[id]).find(Boolean) ?? "Player";
    set(movePlayer(current, { uid: id, name }, teamId));
  }

  function rename(team: DraftedTeam) {
    const name = window.prompt("Team name", team.name)?.trim();
    if (name) set(current.map((t) => (t.id === team.id ? { ...t, name: name.slice(0, 40) } : t)));
  }

  async function save() {
    const problem = draftedTeamsProblem({ division: d, teams: current, locked });
    if (problem) return setError(problem);
    if (await attempt(setBusy, setError, () => draftApi.saveTeams(user, tournamentId, d.id, current))) {
      setDirty(false);
      setNotice("Teams saved.");
    }
  }

  const describe = (id: string) => {
    const s = signupOf(id);
    return [s ? `Skill ${s.skill}` : null, s?.gender ? genderMatchLabels[s.gender] : null].filter(Boolean).join(" · ");
  };

  const menu = (id: string, team: DraftedTeam | null) =>
    created ? null : (
      <select
        aria-label="Move player"
        value=""
        onChange={(e) => {
          const v = e.target.value;
          if (v === "_captain" && team) set(current.map((t) => (t.id === team.id ? { ...t, captainId: id } : t)));
          else if (v === "_none") move(id, null);
          else if (v) move(id, v);
        }}
      >
        <option value="">Move…</option>
        {team && team.captainId !== id && <option value="_captain">Make captain</option>}
        {current
          .filter((t) => t.id !== team?.id)
          .map((t) => (
            <option key={t.id} value={t.id}>
              Move to {t.name}
            </option>
          ))}
        {team && <option value="_none">Take off team</option>}
      </select>
    );

  return (
    <div className="drafts">
      <div className="draft-head">
        <h2 className="draft-title">Draft teams · {divisionLabel(d)}</h2>
        {!created && (
          <button type="button" className="btn btn-primary btn-small" disabled={busy || current.length === 0 || !dirty} onClick={save}>
            {dirty ? "Save teams" : "Teams saved"}
          </button>
        )}
      </div>
      <p className="muted">
        {players.length} accepted {players.length === 1 ? "player" : "players"}
        {current.length === 0 ? "" : ` · ${unassigned.length} not on a team`}
        {mixed ? " · evened by gender match" : ""}.
      </p>
      {error && <p className="form-error">{error}</p>}
      {notice && <p className="muted" role="status">{notice}</p>}

      {created ? (
        <div className="draft-callout">
          <b>The league&apos;s teams are made</b>
          <p>Each captain owns their team and the players are its members. Manage rosters on the teams themselves.</p>
        </div>
      ) : locked ? (
        <div className="draft-callout">
          <b>The schedule is published</b>
          <p>You can move players, rename teams and change captains, but not add or remove teams.</p>
        </div>
      ) : fromCaptains ? (
        <div className="draft-callout">
          <b>Drafted by the captains</b>
          <p>Move players, rename teams or change a captain below, then save.</p>
        </div>
      ) : (
        <section className="card">
          <div className="draft-head">
            <h3 className="card-title">Teams</h3>
            <div className="draft-stepper">
              <button type="button" className="btn btn-small" aria-label="Fewer teams" disabled={teamCount <= 2} onClick={() => setTeamCount(teamCount - 1)}>
                −
              </button>
              <b>{teamCount}</b>
              <button type="button" className="btn btn-small" aria-label="More teams" disabled={teamCount >= maxTeams} onClick={() => setTeamCount(teamCount + 1)}>
                +
              </button>
            </div>
          </div>
          <div className="home-actions">
            <button type="button" className="btn btn-primary btn-small" onClick={() => deal(seed)}>
              {current.length === 0 ? "Deal teams" : "Deal again"}
            </button>
            {current.length > 0 && (
              <button
                type="button"
                className="btn btn-small"
                onClick={() => {
                  setSeed(seed + 1);
                  deal(seed + 1);
                }}
              >
                Shuffle
              </button>
            )}
          </div>
          <p className="muted small">Players are dealt strongest first, each to the team with the fewest players and the lowest total skill. Dealing again replaces the rosters below.</p>
        </section>
      )}

      {stale.length > 0 && !created && (
        <div className="draft-callout">
          <b>{stale.length === 1 ? "1 player is" : `${stale.length} players are`} no longer accepted</b>
          <p>They withdrew or were declined since the draft.</p>
          <button
            type="button"
            className="btn btn-small"
            onClick={() => {
              let next = current;
              for (const id of new Set(stale)) next = movePlayer(next, { uid: id, name: "" }, null);
              set(next);
            }}
          >
            Remove
          </button>
        </div>
      )}

      {current.length > 0 && unassigned.length > 0 && (
        <section className="card">
          <h3 className="card-title">Not on a team</h3>
          <ul className="draft-pool">
            {unassigned.map((p) => (
              <li key={p.id}>
                <span>
                  {p.name} <span className="muted small">{describe(p.id)}</span>
                </span>
                {menu(p.id, null)}
              </li>
            ))}
          </ul>
        </section>
      )}

      <div className="draft-board">
        {current.map((team) => (
          <section key={team.id} className="card draft-team">
            <div className="draft-head">
              <h4 className="card-title">{team.name}</h4>
              {!created && (
                <button type="button" className="text-btn" onClick={() => rename(team)}>
                  Rename
                </button>
              )}
            </div>
            <p className="muted small">
              {team.playerIds.length} players · skill {skillOf(team)}
            </p>
            {team.playerIds.length === 0 ? (
              <p className="muted">No players yet.</p>
            ) : (
              <ul className="draft-roster">
                {team.playerIds.map((id) => (
                  <li key={id}>
                    <span>
                      {signupOf(id)?.name ?? team.playerNames[id] ?? "Player"}
                      <span className="muted small"> {[describe(id), id === team.captainId ? "Captain" : null].filter(Boolean).join(" · ")}</span>
                    </span>
                    {menu(id, team)}
                  </li>
                ))}
              </ul>
            )}
          </section>
        ))}
      </div>
    </div>
  );
}
