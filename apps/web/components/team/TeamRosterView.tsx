"use client";
import {
  groupByLine,
  type PendingInvites,
  type PublicRoster,
  type RosterLine,
  rosterLineLabels,
  rosterLines,
  type RosterMember,
  type RosterPlayer,
  type SetRosterLinesRequest,
  type TeamRoster,
  unassignedLineLabel,
} from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { type Signal, useChangeSignal } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { roleLabel } from "../ProfileDashboard";
import { LocalTime } from "../LocalTime";
import { ErrorNote, Loading } from "../StatusViews";
import { AddMember } from "./AddMember";
import { RolesTab } from "./RolesTab";
import { SegmentedTabs } from "../ui/SegmentedTabs";
import { useTeamHub } from "./TeamContext";
import { StatusPill } from "../ui/StatusPill";
import { ListRow } from "../ui/ListRow";
import { useConfirm } from "@/components/ui/ConfirmDialog";

/** In place of a youth team's roster for anyone who isn't on it (the app says the same). */
export const youthRosterNote = "Rosters of youth teams are private: only members see them.";

const positionLabels: Record<string, string> = { handler: "Handler", cutter: "Cutter", hybrid: "Hybrid" };
/** The line picker's buttons (RosterLine.short in the app). */
const lineShort: Record<RosterLine, string> = { o: "O", d: "D", both: "Both" };

/**
 * Who's on the team, for anyone signed in (`GET /v1/teams/:id/roster`):
 * the roster as a table, then the members, each linking to their profile.
 * Visitors see an adult team's players ([publicRoster], from the server)
 * without links, since players' pages are for members; any other roster
 * (a youth team's, a group's members) asks them to log in. Member managers
 * of any kind invite people (the hub's invite dialog).
 */
export function TeamRosterView({ publicRoster = null, youth = false }: { publicRoster?: PublicRoster | null; youth?: boolean }) {
  const { teamId, kind, viewer } = useTeamHub();
  const { user } = useAuth();
  const [roster, setRoster] = useState<TeamRoster | null>(null);
  const [error, setError] = useState("");
  // A youth team's roster is its members' (and its school or club's admins'): the API refuses anyone else.
  const [youthPrivate, setYouthPrivate] = useState(false);
  const [filter, setFilter] = useState("");
  // Members also have a Roles tab: who holds each tier and custom role.
  const [tab, setTab] = useState<"roster" | "roles">("roster");
  // Bumped after saving lines: they're on the roster docs, not the team doc.
  const [reload, setReload] = useState(0);

  // Members refetch when the team doc changes (someone joins, leaves or
  // changes role); outsiders can't read it, so theirs loads once.
  const member = viewer.state === "member";
  const signals: Signal[] | null = member ? [{ doc: `teams/${teamId}` }] : null;
  const version = useChangeSignal(signals, member ? teamId : "");

  useEffect(() => {
    if (!user) return;
    let live = true;
    setError("");
    setYouthPrivate(false);
    // A moment's wait: subscribing fires every signal at once.
    const timer = setTimeout(() => {
      callApi<TeamRoster>(user, `/v1/teams/${encodeURIComponent(teamId)}/roster`).then(
        (r) => {
          if (live) setRoster(r);
        },
        (e) => {
          if (!live) return;
          if (youth && !member && (e as { status?: number }).status === 403) setYouthPrivate(true);
          else setError(problem(e, "Couldn't load the roster. Try again."));
        },
      );
    }, 150);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [user, teamId, version, youth, member, reload]);
  // Another team, or another account: don't show the last one's roster.
  useEffect(() => setRoster(null), [user, teamId]);

  if (user === undefined) return publicRoster ? <VisitorRoster roster={publicRoster} teamId={teamId} /> : null;
  if (!user) {
    if (publicRoster) return <VisitorRoster roster={publicRoster} teamId={teamId} />;
    return (
      <div className="card hub-empty">
        <p>
          {kind !== "team"
            ? "Only members see who's in this community."
            : youth
              ? youthRosterNote
              : "Only members see this team's roster."}{" "}
          Log in or sign up free.
        </p>
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
  if (youthPrivate && !roster) {
    return (
      <div className="card hub-empty">
        <p>{youthRosterNote}</p>
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

  const showRoles = member && tab === "roles";
  return (
    <div className="stack">
      {member && (
        <SegmentedTabs
          label="Roster sections"
          items={[
            { id: "roster", label: "Roster" },
            { id: "roles", label: "Roles" },
          ]}
          value={tab}
          onChange={(t) => setTab(t as typeof tab)}
        />
      )}
      <div className="toolbar">
        {!showRoles && (
          <input
            className="search-input"
            type="search"
            placeholder="Filter by name, number or role"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            aria-label="Filter the roster"
          />
        )}
        <span className="muted small">
          {roster.kind === "team" && `${roster.players.length} players · `}
          {roster.members.length} {roster.members.length === 1 ? "member" : "members"}
        </span>
        <AddMember roster={roster} onAdded={() => setReload((n) => n + 1)} />
      </div>

      {showRoles && <RolesTab roster={roster} />}

      {!showRoles && roster.kind === "team" && (
        <PlayersCard
          roster={roster}
          players={players}
          canEditLines={viewer.state === "member" && viewer.can("manageTeam")}
          onSaved={() => setReload((n) => n + 1)}
        />
      )}

      {!showRoles && viewer.state === "member" && viewer.can("manageMembers") && <PendingInvitesCard teamId={teamId} version={version} />}

      {!showRoles && (
      <section className="roster-section">
        <h2 className="card-title">Members</h2>
        {members.length === 0 ? (
          <p className="muted small">No one matches.</p>
        ) : (
          <ul className="roster-rows">
            {members.map((m) => (
              <MemberCard key={m.uid} member={m} kind={roster.kind} me={m.uid === user.uid} />
            ))}
          </ul>
        )}
      </section>
      )}
    </div>
  );
}

/** An adult team's players as visitors see them: names, numbers and positions, no links. */
function VisitorRoster({ roster, teamId }: { roster: PublicRoster; teamId: string }) {
  const [filter, setFilter] = useState("");
  const q = filter.trim().toLowerCase();
  const players = roster.players.filter(
    (p) => !q || [p.name, p.username, p.number?.toString(), p.position].some((x) => x?.toLowerCase().includes(q)),
  );
  const next = encodeURIComponent(`/teams/${teamId}/roster`);
  return (
    <div className="stack">
      <div className="toolbar">
        <input
          className="search-input"
          type="search"
          placeholder="Filter by name, number or position"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          aria-label="Filter the roster"
        />
        <span className="muted small">{roster.players.length} players</span>
      </div>
      <section className="roster-section">
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
                {players.map((p, i) => (
                  <tr key={`${i}-${p.name}`}>
                    <td className="num">{p.number ?? "–"}</td>
                    <td>
                      <span className="person">
                        <Avatar name={p.name} url={p.photoUrl} size={28} />
                        <span>
                          {p.name}
                          {p.username && <small className="muted"> @{p.username}</small>}
                        </span>
                      </span>
                    </td>
                    <td>{positionLabels[p.position ?? ""] ?? "–"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
      <p className="muted small">
        <Link href={`/sign-in?next=${next}`}>Log in</Link> to see players&apos; profiles, the team&apos;s members and
        their roles.
      </p>
    </div>
  );
}

const leads = new Set(["owner", "coach", "captain"]);

/**
 * The roster's players: one table, or one per line (O-line, D-line, Both
 * lines, Unassigned; groupByLine) once anyone has a line. Each row has
 * the linked member's role (their tier as a pill when they run the team,
 * then custom roles). The team's admins (manageTeam) get "Edit lines":
 * O / D / Both on every row, saved together (`PUT .../roster-lines`).
 */
function PlayersCard({
  roster,
  players,
  canEditLines,
  onSaved,
}: {
  roster: TeamRoster;
  players: RosterPlayer[];
  canEditLines: boolean;
  onSaved: () => void;
}) {
  const { teamId, kind } = useTeamHub();
  const { user } = useAuth();
  const [draft, setDraft] = useState<Record<string, RosterLine | null> | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const members = new Map(roster.members.map((m) => [m.uid, m]));
  const editing = draft !== null;
  const lineOf = (p: RosterPlayer): RosterLine | undefined => (draft && p.id in draft ? (draft[p.id] ?? undefined) : p.line);
  const groups = editing ? [] : groupByLine(players);

  async function save() {
    if (!user || !draft) return;
    const lines: SetRosterLinesRequest["lines"] = {};
    for (const p of roster.players) if (p.id in draft && (draft[p.id] ?? undefined) !== p.line) lines[p.id] = draft[p.id];
    if (Object.keys(lines).length === 0) return setDraft(null);
    setSaving(true);
    setError("");
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/roster-lines`, { method: "PUT", body: { lines } satisfies SetRosterLinesRequest });
      setDraft(null);
      onSaved();
    } catch (e) {
      setError(problem(e, "Couldn't save the lines. Try again."));
    } finally {
      setSaving(false);
    }
  }

  const table = (rows: RosterPlayer[]) => (
    <div className="table-scroll">
      <table className="data-table roster-table">
        <thead>
          <tr>
            <th className="num">#</th>
            <th>Player</th>
            <th>Role</th>
            <th>Position</th>
            {editing && <th>Line</th>}
          </tr>
        </thead>
        <tbody>
          {rows.map((p) => {
            const m = p.person ? members.get(p.person.uid) : undefined;
            return (
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
                <td>
                  {m && (leads.has(m.tier) || m.roles.length > 0) ? (
                    <span className="roster-role">
                      {leads.has(m.tier) && <span className="role-pill lead">{roleLabel(m.tier, kind)}</span>}
                      {m.roles.map((r) => (
                        <StatusPill key={r}>{r}</StatusPill>
                      ))}
                    </span>
                  ) : (
                    <span className="muted">{m ? roleLabel(m.tier, kind) : "–"}</span>
                  )}
                </td>
                <td>{positionLabels[p.position ?? ""] ?? "–"}</td>
                {editing && (
                  <td>
                    <span className="line-picker" role="group" aria-label={`Line for ${p.name}`}>
                      {rosterLines.map((l) => {
                        const on = lineOf(p) === l;
                        return (
                          <button
                            key={l}
                            type="button"
                            aria-pressed={on}
                            title={rosterLineLabels[l]}
                            onClick={() => setDraft((d) => ({ ...d, [p.id]: on ? null : l }))}
                          >
                            {lineShort[l]}
                          </button>
                        );
                      })}
                    </span>
                  </td>
                )}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );

  return (
    <section className="roster-section">
      <h2 className="card-title">Roster</h2>
      {canEditLines && roster.players.length > 0 && (
        <div className="lines-bar">
          <p className="muted small">{editing ? "Pick O, D or Both for each player." : "Group the roster into O-line and D-line."}</p>
          {editing ? (
            <>
              <button type="button" className="btn btn-small btn-quiet" disabled={saving} onClick={() => setDraft(null)}>
                Cancel
              </button>
              <button type="button" className="btn btn-small btn-primary" disabled={saving} onClick={() => void save()}>
                {saving ? "Saving…" : "Save lines"}
              </button>
            </>
          ) : (
            <button type="button" className="btn btn-small" onClick={() => setDraft({})}>
              Edit lines
            </button>
          )}
        </div>
      )}
      {error && <ErrorNote>{error}</ErrorNote>}
      {roster.players.length === 0 ? (
        <p className="muted small">No players on the roster yet.</p>
      ) : groups.length === 0 ? (
        table(players)
      ) : (
        groups.map((g) => (
          <div key={g.line ?? "none"}>
            <h3 className="line-group-title">
              {g.line ? rosterLineLabels[g.line] : unassignedLineLabel} · {g.players.length}
            </h3>
            {table(g.players)}
          </div>
        ))
      )}
    </section>
  );
}

/**
 * "Invites pending": who's invited and hasn't answered
 * (`GET /v1/teams/:id/invites`), for those who invite people, each with
 * who invited them and Withdraw. Neutral: it's the invitees' move.
 * Refetches when the team doc changes ([version]: someone joins).
 */
function PendingInvitesCard({ teamId, version }: { teamId: string; version: number }) {
  const askConfirm = useConfirm();
  const { user } = useAuth();
  const [invites, setInvites] = useState<PendingInvites["invites"] | null>(null);
  const [error, setError] = useState("");
  const [reload, setReload] = useState(0);
  useEffect(() => {
    if (!user) return;
    let live = true;
    callApi<PendingInvites>(user, `/v1/teams/${encodeURIComponent(teamId)}/invites`).then(
      (r) => live && setInvites(r.invites),
      () => live && setInvites([]),
    );
    return () => {
      live = false;
    };
  }, [user, teamId, version, reload]);
  if (!invites || invites.length === 0) return null;

  async function withdraw(uid: string, name: string) {
    if (!user || !(await askConfirm({ message: `Withdraw the invite to ${name}?\n\nThey won't be able to join with it any more.`, confirmLabel: "Withdraw", destructive: true }))) return;
    setError("");
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/invites/${encodeURIComponent(uid)}`, { method: "DELETE" });
      setReload((n) => n + 1);
    } catch (e) {
      setError(problem(e, "Couldn't withdraw the invite. Try again."));
    }
  }

  return (
    <section className="roster-section">
      <h2 className="card-title">Invites pending · {invites.length}</h2>
      {error && <ErrorNote>{error}</ErrorNote>}
      <ul className="invite-rows">
        {invites.map((i) => (
          <li key={i.uid}>
            <Avatar name={i.name} url={i.photoUrl} size={32} />
            <span>
              <b>{i.name}</b>
              <small className="muted">
                {i.invitedByName ? `Invited by ${i.invitedByName}` : "Invited"}
                {i.invitedAt && (
                  <>
                    {" · "}
                    <LocalTime iso={i.invitedAt} style="date" />
                  </>
                )}
              </small>
            </span>
            <button type="button" className="btn btn-small btn-quiet" onClick={() => void withdraw(i.uid, i.name)}>
              Withdraw
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}

/**
 * A member's row (a ListRow, C3): who they are, then their role as a pill (accent for those who run the
 * team, so captains and coaches stand out; neutral otherwise) and custom roles.
 */
function MemberCard({ member, kind, me }: { member: RosterMember; kind: string; me: boolean }) {
  const tier = roleLabel(member.tier, kind);
  return (
    <li>
      <ListRow
        href={`/players/${member.uid}`}
        leading={<Avatar name={member.name} url={member.photoUrl} size={40} />}
        title={
          <>
            {member.name}
            {me && <span className="muted"> (you)</span>}
          </>
        }
        subtitle={member.username ? `@${member.username}` : undefined}
        trailing={
          <span className="member-roles">
            <StatusPill tone={leads.has(member.tier) ? "accent" : "neutral"}>{tier}</StatusPill>
            {member.roles.map((r) => (
              <StatusPill key={r}>{r}</StatusPill>
            ))}
          </span>
        }
      />
    </li>
  );
}
