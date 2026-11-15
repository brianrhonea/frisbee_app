"use client";
import type { RosterMember, TeamRoster } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { type Signal, useChangeSignal } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { roleLabel } from "../ProfileDashboard";
import { ErrorNote, Loading } from "../StatusViews";
import { InviteButton } from "./InviteDialog";
import { useTeamHub } from "./TeamContext";

const positionLabels: Record<string, string> = { handler: "Handler", cutter: "Cutter", hybrid: "Hybrid" };

/**
 * Who's on the team, for anyone signed in (`GET /v1/teams/:id/roster`):
 * the roster as a table, then the members, each linking to their profile.
 * Visitors are asked to log in; member managers of any kind invite people
 * (the hub's invite dialog).
 */
export function TeamRosterView() {
  const { teamId, kind, viewer } = useTeamHub();
  const { user } = useAuth();
  const [roster, setRoster] = useState<TeamRoster | null>(null);
  const [error, setError] = useState("");
  const [filter, setFilter] = useState("");

  // Members refetch when the team doc changes (someone joins, leaves or
  // changes role); outsiders can't read it, so theirs loads once.
  const member = viewer.state === "member";
  const signals: Signal[] | null = member ? [{ doc: `teams/${teamId}` }] : null;
  const version = useChangeSignal(signals, member ? teamId : "");

  useEffect(() => {
    if (!user) return;
    let live = true;
    setError("");
    // A moment's wait: subscribing fires every signal at once.
    const timer = setTimeout(() => {
      callApi<TeamRoster>(user, `/v1/teams/${encodeURIComponent(teamId)}/roster`).then(
        (r) => {
          if (live) setRoster(r);
        },
        (e) => {
          if (live) setError(problem(e, "Couldn't load the roster. Try again."));
        },
      );
    }, 150);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [user, teamId, version]);
  // Another team, or another account: don't show the last one's roster.
  useEffect(() => setRoster(null), [user, teamId]);

  if (user === undefined) return null;
  if (!user) {
    return (
      <div className="card hub-empty">
        <p>Log in to see who&apos;s on this {kind === "team" ? "team" : "group"}. It&apos;s free.</p>
        <div className="home-actions">
          <Link className="btn btn-primary btn-small" href={`/sign-in?next=${encodeURIComponent(`/teams/${teamId}/roster`)}`}>
            Log in
          </Link>
          <Link className="btn btn-small" href={`/sign-up?next=${encodeURIComponent(`/teams/${teamId}/roster`)}`}>
            Sign up
          </Link>
        </div>
      </div>
    );
  }
  // A failed refetch keeps the roster already showing.
  if (error && !roster) return <ErrorNote>{error}</ErrorNote>;
  if (!roster) return <Loading label="Loading the roster…" />;

  const q = filter.trim().toLowerCase();
  const match = (...s: Array<string | undefined>) => !q || s.some((x) => x?.toLowerCase().includes(q));
  const players = roster.players.filter((p) => match(p.name, p.person?.username, p.number?.toString(), p.position));
  const members = roster.members.filter((m) => match(m.name, m.username, ...m.roles));

  return (
    <div className="stack">
      <div className="toolbar">
        <input
          className="search-input"
          type="search"
          placeholder="Filter by name, number or role"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          aria-label="Filter the roster"
        />
        <span className="muted small">
          {roster.kind === "team" && `${roster.players.length} players · `}
          {roster.members.length} {roster.members.length === 1 ? "member" : "members"}
        </span>
        <InviteButton />
      </div>

      {roster.kind === "team" && (
        <section className="card">
          <h2 className="card-title">Roster</h2>
          {roster.players.length === 0 ? (
            <p className="muted small">No players on the roster yet.</p>
          ) : (
            <div className="table-scroll">
              <table className="data-table roster-table">
                <thead>
                  <tr>
                    <th className="num">#</th>
                    <th>Player</th>
                    <th>Position</th>
                  </tr>
                </thead>
                <tbody>
                  {players.map((p) => (
                    <tr key={p.id}>
                      <td className="num">{p.number ?? "–"}</td>
                      <td>
                        {p.person ? (
                          <Link className="person" href={`/players/${p.person.uid}`}>
                            <Avatar name={p.person.name} url={p.person.photoUrl} size={28} />
                            <span>
                              {p.name}
                              {p.person.username && <small className="muted"> @{p.person.username}</small>}
                            </span>
                          </Link>
                        ) : (
                          <span className="person">
                            <Avatar name={p.name} size={28} />
                            <span>{p.name}</span>
                          </span>
                        )}
                      </td>
                      <td>{positionLabels[p.position ?? ""] ?? "–"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      )}

      <section className="card">
        <h2 className="card-title">Members</h2>
        {members.length === 0 ? (
          <p className="muted small">No one matches.</p>
        ) : (
          <ul className="member-grid">
            {members.map((m) => (
              <MemberCard key={m.uid} member={m} kind={roster.kind} me={m.uid === user.uid} />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function MemberCard({ member, kind, me }: { member: RosterMember; kind: string; me: boolean }) {
  const tier = member.tier === "player" ? null : roleLabel(member.tier, kind);
  return (
    <li>
      <Link href={`/players/${member.uid}`} className="member-card">
        <Avatar name={member.name} url={member.photoUrl} size={44} />
        <span>
          <b>
            {member.name}
            {me && <span className="muted"> (you)</span>}
          </b>
          {member.username && <small className="muted">@{member.username}</small>}
          {(tier || member.roles.length > 0) && (
            <span className="member-roles">
              {tier && <span className="pill">{tier}</span>}
              {member.roles.map((r) => (
                <span key={r} className="pill pill-soft">
                  {r}
                </span>
              ))}
            </span>
          )}
        </span>
      </Link>
    </li>
  );
}
