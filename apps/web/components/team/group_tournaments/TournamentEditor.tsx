"use client";
import {
  type GroupPlayer,
  type GroupSchedulePlan,
  type GroupTournamentDoc,
  type GroupTournamentSettings,
  type GroupTournamentTeam,
  GroupScheduleError,
  type SaveGroupTournamentRequest,
  type SaveTeamEventRequest,
  groupEngine,
  groupTournamentFormatInfo,
  groupTournamentFormats,
  groupTournamentLimits,
  tournamentFollowKey,
} from "@stall10/shared";
import { where } from "firebase/firestore";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { useAuth } from "../../AuthProvider";
import { callApi } from "@/lib/client";
import { type Doc, useLiveDoc, useLiveQuery } from "@/lib/live";
import { type TeamDoc, useTeamHub } from "../TeamContext";
import { MembersOnlySection } from "../TeamNav";
import type { TeamEventDoc } from "../TeamSchedule";
import { gameTime, shortDay, slotLabel, tournamentDates, tournamentView, tournamentWhen } from "./format";
import "./group_tournaments.css";

/**
 * Sets a tournament up (/teams/:id/tournaments/new, or .../:id/edit):
 * details, format, teams and rules, a schedule preview, and players on
 * teams. Organizers only (TournamentEditorScreen in the app).
 */
export function TournamentEditorPage({ tournamentId, eventId }: { tournamentId: string | null; eventId?: string | null }) {
  const { teamId, kind, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const organizer = member?.can("manageEvents") ?? false;
  const doc = useLiveDoc<GroupTournamentDoc>(organizer && tournamentId ? `teams/${teamId}/groupTournaments/${tournamentId}` : null);
  const events = useLiveQuery<TeamEventDoc>(organizer ? `teams/${teamId}/events` : null, [where("type", "==", "tournament")], "tournamentEvents");
  const back = (
    <Link href={`/teams/${encodeURIComponent(teamId)}/more?tab=tournaments`} className="text-btn">
      ← Tournaments
    </Link>
  );

  if (viewer.state === "loading") return <p className="muted" aria-busy="true">Loading…</p>;
  if (!member) return <MembersOnlySection what="tournaments" />;
  if (kind === "team") return <p className="empty">Teams don&apos;t run their own tournaments. {back}</p>;
  if (!organizer) return <p className="empty">Only the group&apos;s organizers set tournaments up. {back}</p>;
  if (tournamentId) {
    if (doc.error) return <p className="form-error">{doc.error}</p>;
    if (doc.data === undefined) return <p className="muted" aria-busy="true">Loading…</p>;
    if (doc.data === null) return <p className="empty">Tournament not found. {back}</p>;
  }
  if (events.data === undefined && !events.error) return <p className="muted" aria-busy="true">Loading…</p>;
  return (
    <div className="stack">
      {back}
      {/* Keyed so later snapshots (our own saves) don't reset the draft. */}
      <Editor key={tournamentId ?? "new"} teamId={teamId} group={member.team} initial={doc.data ?? null} initialEventId={eventId ?? null} events={events.data ?? []} />
    </div>
  );
}

/** Next Saturday, 9 AM. */
function defaultStart(): string {
  const now = new Date();
  const days = (6 - now.getDay() + 7) % 7 || 7;
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + days, 9).toISOString();
}

const dateKey = (d: Date) => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;

/** Days after [first] up to [last]'s date, each at [first]'s time unless [keep] has a start that day. */
function laterDaysBetween(first: string, last: string, keep: string[] = []): string[] {
  const f = new Date(first);
  const byDate = new Map(keep.map((k) => [dateKey(new Date(k)), k]));
  const l = new Date(last);
  const lastDate = new Date(l.getFullYear(), l.getMonth(), l.getDate());
  const out: string[] = [];
  for (let day = new Date(f.getFullYear(), f.getMonth(), f.getDate() + 1); day <= lastDate; day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)) {
    out.push(byDate.get(dateKey(day)) ?? new Date(day.getFullYear(), day.getMonth(), day.getDate(), f.getHours(), f.getMinutes()).toISOString());
    if (out.length >= groupTournamentLimits.laterDays) break;
  }
  return out;
}

const pad = (n: number) => String(n).padStart(2, "0");
const dateInput = (iso: string) => {
  const d = new Date(iso);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const timeInput = (iso: string) => {
  const d = new Date(iso);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
};
const localInput = (iso: string | null) => (iso ? `${dateInput(iso)}T${timeInput(iso)}` : "");
const fromDateInput = (v: string) => {
  const [y, m, d] = v.split("-").map(Number);
  return y && m && d ? new Date(y, m - 1, d) : null;
};

function Editor({
  teamId,
  group,
  initial,
  initialEventId,
  events: allEvents,
}: {
  teamId: string;
  group: Doc<TeamDoc>;
  initial: Doc<GroupTournamentDoc> | null;
  initialEventId: string | null;
  events: Array<Doc<TeamEventDoc>>;
}) {
  const { user } = useAuth();
  const router = useRouter();
  const start = initial ? tournamentView(initial) : null;
  const [id, setId] = useState<string | null>(start?.id ?? null);
  const [name, setName] = useState(start?.name ?? "");
  const [eventId, setEventIdState] = useState<string | null>(start?.eventId ?? null);
  const [settings, setSettings] = useState<GroupTournamentSettings>(
    () =>
      start?.settings ?? {
        format: "poolsSingleElim",
        playersOnField: 5,
        poolCount: 2,
        gameMinutes: 40,
        breakMinutes: 10,
        scoreCap: 11,
        timeoutsPerHalf: 1,
        fields: 1,
        startsAt: defaultStart(),
        idealEndsAt: null,
        laterDays: [],
        scoring: "points",
      },
  );
  const [teams, setTeams] = useState<GroupTournamentTeam[]>(() => start?.teams ?? groupEngine.blankTeams(groupTournamentLimits.defaultTeams));
  /** Players brought in who aren't on a team yet (not saved, as in the app). */
  const [bench, setBench] = useState<GroupPlayer[]>([]);
  const [published, setPublished] = useState(start ? start.status !== "setup" : false);
  const [publishedTeams, setPublishedTeams] = useState(() => (start && start.status !== "setup" ? start.teams.map((t) => t.id).sort().join("|") : ""));
  const [plan, setPlan] = useState<GroupSchedulePlan | null>(null);
  const [planError, setPlanError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"save" | "publish" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [announce, setAnnounce] = useState<{ page: string; id: string } | null>(null);
  const [adding, setAdding] = useState("");
  const isNew = id === null;

  // Upcoming Tournament events whose RSVPs can supply players.
  const dayAgo = Date.now() - 86_400_000;
  const tournamentEvents = useMemo(
    () => allEvents.filter((e) => Date.parse(e.endsAt ?? e.startsAt ?? "") >= dayAgo).sort((a, b) => (a.startsAt ?? "").localeCompare(b.startsAt ?? "")),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- dayAgo moves every render.
    [allEvents],
  );
  // The linked event, even if its type changed since (so it isn't in the list).
  const linkedDoc = useLiveDoc<TeamEventDoc>(eventId ? `teams/${teamId}/events/${eventId}` : null);
  const event = allEvents.find((e) => e.id === eventId) ?? linkedDoc.data ?? null;
  const nameOf = (uid: string) => group.memberNames?.[uid] ?? "Player";
  const isMemberUid = (uid: string) => Object.hasOwn(group.members ?? {}, uid);

  const clearPlan = () => setPlan(null);

  // Opened from an event ("?event="): a new tournament takes its name, days and times.
  const linkedOnce = useRef(false);
  useEffect(() => {
    if (linkedOnce.current || start || !initialEventId) return;
    linkedOnce.current = true;
    setEvent(initialEventId);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once, on open.
  }, []);
  const updateSettings = (s: GroupTournamentSettings) => {
    setSettings(s);
    clearPlan();
  };

  function setEvent(next: string | null) {
    setEventIdState(next);
    const e = allEvents.find((x) => x.id === next);
    if (e && e.startsAt && isNew) {
      if (!name.trim()) setName(e.title ?? "");
      const end = e.endsAt ?? null;
      updateSettings({ ...settings, startsAt: e.startsAt, laterDays: laterDaysBetween(e.startsAt, end ?? e.startsAt), idealEndsAt: end });
    } else clearPlan();
  }

  function setDates(first: Date, last: Date) {
    const s = new Date(settings.startsAt);
    const startsAt = new Date(first.getFullYear(), first.getMonth(), first.getDate(), s.getHours(), s.getMinutes()).toISOString();
    updateSettings({ ...settings, startsAt, laterDays: laterDaysBetween(startsAt, (last < first ? first : last).toISOString(), settings.laterDays) });
  }

  function setDayStart(index: number, hhmm: string) {
    const [h, m] = hhmm.split(":").map(Number);
    if (h === undefined || m === undefined || Number.isNaN(h) || Number.isNaN(m)) return;
    const days = [settings.startsAt, ...settings.laterDays];
    const d = new Date(days[index]!);
    days[index] = new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m).toISOString();
    updateSettings({ ...settings, startsAt: days[0]!, laterDays: days.slice(1) });
  }

  // ---- Players and teams (team_builder) ----
  const placed = new Set([...teams.flatMap((t) => t.playerIds), ...bench.map((p) => p.uid)]);
  const rsvps = (status: string) =>
    Object.entries(event?.rsvps ?? {})
      .filter(([u, s]) => s === status && isMemberUid(u))
      .map(([u]) => ({ uid: u, name: nameOf(u) }));
  const going = rsvps("going");
  const maybe = rsvps("maybe");
  const otherMembers = Object.keys(group.members ?? {})
    .filter((u) => !placed.has(u))
    .map((u) => ({ uid: u, name: nameOf(u) }))
    .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
  const allPlayers: GroupPlayer[] = [...teams.flatMap((t) => t.playerIds.map((u) => ({ uid: u, name: t.playerNames[u] ?? "Player" }))), ...bench];

  function importRsvps() {
    const added = [...going, ...maybe].filter((p, i, xs) => !placed.has(p.uid) && xs.findIndex((x) => x.uid === p.uid) === i);
    setBench([...bench, ...added]);
    clearPlan();
    setNote(added.length === 0 ? "Everyone is already in" : `Added ${added.length} player${added.length === 1 ? "" : "s"}`);
  }

  function setTeamCount(count: number) {
    const n = Math.min(Math.max(count, 2), groupTournamentLimits.teams);
    if (n > teams.length) setTeams([...teams, ...groupEngine.blankTeams(n - teams.length, teams)]);
    else if (n < teams.length) {
      const removed = teams.slice(n);
      setTeams(teams.slice(0, n));
      setBench([...bench, ...removed.reverse().flatMap((t) => t.playerIds.map((u) => ({ uid: u, name: t.playerNames[u] ?? "Player" })))]);
    }
    clearPlan();
  }

  function removeTeam(teamIdToRemove: string) {
    const team = teams.find((t) => t.id === teamIdToRemove);
    if (!team) return;
    setTeams(teams.filter((t) => t.id !== teamIdToRemove));
    setBench([...bench, ...team.playerIds.map((u) => ({ uid: u, name: team.playerNames[u] ?? "Player" }))]);
    clearPlan();
  }

  function movePlayerTo(player: GroupPlayer, to: string | null) {
    setTeams(groupEngine.movePlayer(teams, player, to));
    setBench([...bench.filter((p) => p.uid !== player.uid), ...(to === null ? [player] : [])]);
  }

  function setCaptain(team: string, uid: string) {
    setTeams(teams.map((t) => (t.id === team && t.playerIds.includes(uid) ? { ...t, captainId: uid } : t)));
  }

  function renameTeam(team: string, value: string) {
    const n = value.trim();
    if (!n) return;
    setTeams(teams.map((t) => (t.id === team ? { ...t, name: n.slice(0, groupTournamentLimits.teamName) } : t)));
  }

  function assignTeams() {
    const each = Math.floor(allPlayers.length / teams.length);
    const sizes = allPlayers.length % teams.length === 0 ? `${each}` : `${each}–${each + 1}`;
    const ok = window.confirm(
      `All ${allPlayers.length} players are dealt at random into the ${teams.length} teams (${sizes} each), replacing who is on them now. Each team gets a random captain.`,
    );
    if (!ok) return;
    setTeams(groupEngine.dealPlayers(allPlayers, teams));
    setBench([]);
  }

  // ---- Checks ----
  const teamsKey = teams.map((t) => t.id).sort().join("|");
  const teamsChanged = published && teamsKey !== publishedTeams;
  const problem = !name.trim() ? "Give the tournament a name." : teams.length < 2 ? "Add at least two teams." : null;
  const saveProblem = !name.trim() ? "Give the tournament a name." : teamsChanged ? "The number of teams changed: publish the schedule again." : null;
  const empty = teams.filter((t) => t.playerIds.length === 0).length;
  const noCaptain = teams.filter((t) => t.playerIds.length > 0 && !t.captainId).length;
  const todoParts = [
    ...(empty ? [`${empty} team${empty === 1 ? "" : "s"} without players`] : []),
    ...(noCaptain ? [`${noCaptain} team${noCaptain === 1 ? "" : "s"} without a captain`] : []),
  ];
  const todo = todoParts.length ? todoParts.join(" · ") : null;

  const draft = (): SaveGroupTournamentRequest => ({
    name: name.trim(),
    eventId,
    settings,
    teams: teams.map((t) => ({ id: t.id, name: t.name, captainId: t.captainId, playerIds: t.playerIds, playerNames: t.playerNames })),
  });
  const schedule = () => groupEngine.scheduleFor(teams.map((t) => t.id), settings);

  function previewSchedule() {
    try {
      setPlan(schedule());
      setPlanError(null);
    } catch (e) {
      setPlan(null);
      setPlanError(e instanceof GroupScheduleError ? e.message : "Couldn't make a schedule.");
    }
  }

  /**
   * Puts the tournament on the group's schedule: creates its Tournament
   * event, or keeps the linked one's title and times in step (RSVPs,
   * place and notes stay). Returns the event id.
   */
  async function syncEvent(): Promise<string> {
    let endsAt: string | null = null;
    try {
      endsAt = schedule().endsAt;
    } catch {
      endsAt = null;
    }
    if (settings.idealEndsAt && (endsAt === null || Date.parse(settings.idealEndsAt) > Date.parse(endsAt))) endsAt = settings.idealEndsAt;
    const title = name.trim();
    const base = `/v1/teams/${encodeURIComponent(teamId)}/events`;
    if (event) {
      const body: SaveTeamEventRequest = {
        title,
        type: (event.type as SaveTeamEventRequest["type"]) ?? "tournament",
        startsAt: settings.startsAt,
        endsAt,
        location: event.location ?? "",
        notes: event.notes ?? "",
        public: event.public === true,
        poll: event.poll?.question && event.poll.options?.length ? { question: event.poll.question, options: event.poll.options, multiple: event.poll.multiple === true } : null,
      };
      return (await callApi<{ id: string }>(user!, `${base}/${encodeURIComponent(event.id)}`, { method: "PATCH", body })).id;
    }
    const body: SaveTeamEventRequest = { title, type: "tournament", startsAt: settings.startsAt, endsAt };
    return (await callApi<{ id: string }>(user!, base, { method: "POST", body })).id;
  }

  /** Saves (creating it the first time) and returns the tournament id. */
  async function write(publishing: boolean): Promise<string> {
    const linked = await syncEvent();
    setEventIdState(linked);
    const body = { ...draft(), eventId: linked };
    const api = `/v1/teams/${encodeURIComponent(teamId)}/group-tournaments`;
    if (id === null) {
      const res = await callApi<{ id: string }>(user!, api, { method: "POST", body });
      setId(res.id);
      if (publishing) await callApi(user!, `${api}/${encodeURIComponent(res.id)}/schedule`, { method: "POST", body });
      return res.id;
    }
    // Publishing saves the tournament with its new schedule in one call.
    if (publishing) await callApi(user!, `${api}/${encodeURIComponent(id)}/schedule`, { method: "POST", body });
    else await callApi(user!, `${api}/${encodeURIComponent(id)}`, { method: "PUT", body });
    return id;
  }

  async function save() {
    if (!user || saveProblem) return;
    setBusy("save");
    setError(null);
    try {
      await write(false);
      setNote("Saved");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(null);
    }
  }

  async function publish() {
    if (!user || problem) return;
    if (published && !window.confirm("Publish a new schedule? This replaces every game, including scores already entered.")) return;
    const first = !published;
    let p: GroupSchedulePlan;
    try {
      p = schedule();
    } catch (e) {
      setError((e as Error).message);
      return;
    }
    setBusy("publish");
    setError(null);
    try {
      const saved = await write(true);
      setPublished(true);
      setPublishedTeams(teamsKey);
      setPlan(p);
      const page = `/teams/${encodeURIComponent(teamId)}/tournaments/${encodeURIComponent(saved)}`;
      if (first && window.confirm(`Tell the group? Post ${name.trim()} to the group feed so people see it and sign up. You can edit the post first.`)) {
        setAnnounce({ page, id: saved });
      } else router.push(page);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(null);
    }
  }

  if (announce) {
    return <Announcement teamId={teamId} tournamentId={announce.id} group={group} name={name.trim()} settings={settings} teamCount={teams.length} event={event} onDone={() => router.push(announce.page)} />;
  }

  const s = settings;
  const days = [s.startsAt, ...s.laterDays];
  const names = new Map(teams.map((t) => [t.id, t.name]));
  const overrun = plan ? groupEngine.overrunMinutes(plan, s.idealEndsAt) : 0;
  const status = problem ?? (teamsChanged ? saveProblem : null) ?? (todo === null ? "Ready to publish." : `${todo}. You can still publish and add players later.`);

  return (
    <form className="stack gt-editor" onSubmit={(e: FormEvent) => e.preventDefault()}>
      <h2 className="gt-title">{isNew ? "New tournament" : "Tournament setup"}</h2>

      <section className="card settings-form">
        <h3 className="card-title">Details</h3>
        <label>
          Name
          <input value={name} maxLength={groupTournamentLimits.name} onChange={(e) => setName(e.target.value)} />
        </label>
        <label>
          Tournament event <small className="muted">Players come from its RSVPs</small>
          <select value={eventId ?? ""} onChange={(e) => setEvent(e.target.value || null)}>
            <option value="">None</option>
            {tournamentEvents.map((e) => (
              <option key={e.id} value={e.id}>
                {e.title || "Tournament"} · {e.startsAt ? shortDay(e.startsAt) : ""}
              </option>
            ))}
          </select>
        </label>
        {tournamentEvents.length === 0 && <p className="muted small">No upcoming Tournament events. Post one in Events so people can say whether they are coming.</p>}
        <div className="form-grid">
          <label>
            First day
            <input
              type="date"
              value={dateInput(s.startsAt)}
              onChange={(e) => {
                const f = fromDateInput(e.target.value);
                if (f) setDates(f, new Date(days[days.length - 1]!) < f ? f : new Date(days[days.length - 1]!));
              }}
            />
          </label>
          <label>
            Last day
            <input
              type="date"
              value={dateInput(days[days.length - 1]!)}
              min={dateInput(s.startsAt)}
              onChange={(e) => {
                const l = fromDateInput(e.target.value);
                if (l) setDates(new Date(s.startsAt), l);
              }}
            />
          </label>
        </div>
        <p className="muted small">{tournamentDates(s)}</p>
        <div className="gt-days">
          {days.map((d, i) => (
            <label key={i}>
              {days.length === 1 ? "Start time" : `Day ${i + 1} · ${shortDay(d)}`}
              <input type="time" value={timeInput(d)} onChange={(e) => setDayStart(i, e.target.value)} />
            </label>
          ))}
        </div>
        <label>
          Ideal end <small className="muted">{s.idealEndsAt ? tournamentWhen(s.idealEndsAt) : "Not set"}</small>
          <span className="gt-inline">
            <input
              type="datetime-local"
              value={localInput(s.idealEndsAt)}
              onChange={(e) => {
                const t = e.target.value ? new Date(e.target.value) : null;
                updateSettings({ ...s, idealEndsAt: t && !Number.isNaN(t.getTime()) ? t.toISOString() : null });
              }}
            />
            {s.idealEndsAt && (
              <button type="button" className="text-btn" onClick={() => updateSettings({ ...s, idealEndsAt: null })}>
                Clear
              </button>
            )}
          </span>
        </label>
      </section>

      <section className="card settings-form">
        <h3 className="card-title">Format, teams and rules</h3>
        <fieldset>
          <legend>Format</legend>
          {groupTournamentFormats.map((f) => (
            <label key={f} className="gt-radio">
              <input type="radio" name="format" checked={s.format === f} onChange={() => updateSettings({ ...s, format: f })} />
              <span>
                {groupTournamentFormatInfo[f].label}
                <small className="muted"> {groupTournamentFormatInfo[f].summary}</small>
              </span>
            </label>
          ))}
        </fieldset>
        <fieldset>
          <legend>Players on the field</legend>
          <div className="segmented">
            {groupTournamentLimits.fieldSizes.map((n) => (
              <button key={n} type="button" className={s.playersOnField === n ? "on" : ""} onClick={() => updateSettings({ ...s, playersOnField: n })}>
                {n}v{n}
              </button>
            ))}
          </div>
        </fieldset>
        <div className="form-grid">
          <NumberField label="Teams" value={teams.length} min={2} max={groupTournamentLimits.teams} onChange={setTeamCount} />
          {s.format === "poolsSingleElim" && (
            <NumberField label="Pools" value={s.poolCount} min={1} max={Math.min(Math.max(Math.floor(teams.length / 2), 1), 8)} onChange={(v) => updateSettings({ ...s, poolCount: v })} />
          )}
          <NumberField label="Game length (min)" value={s.gameMinutes} min={10} max={120} step={5} onChange={(v) => updateSettings({ ...s, gameMinutes: v })} />
          <NumberField label="Break between games (min)" value={s.breakMinutes} min={0} max={60} step={5} onChange={(v) => updateSettings({ ...s, breakMinutes: v })} />
          <NumberField label="Game to (points)" value={s.scoreCap} min={3} max={21} onChange={(v) => updateSettings({ ...s, scoreCap: v })} />
          <NumberField label="Timeouts per half" value={s.timeoutsPerHalf} min={0} max={4} onChange={(v) => updateSettings({ ...s, timeoutsPerHalf: v })} />
          <NumberField label="Fields" value={s.fields} min={1} max={12} onChange={(v) => updateSettings({ ...s, fields: v })} />
        </div>
      </section>

      <section className="card stack">
        <h3 className="card-title">Schedule</h3>
        <div>
          <button type="button" className="btn btn-small" disabled={teams.length < 2} onClick={previewSchedule}>
            {plan ? "Refresh preview" : "Preview schedule"}
          </button>
        </div>
        {planError && <p className="form-error">{planError}</p>}
        {plan && (
          <div className="stack gt-preview">
            <p>
              {plan.days.length === 1 ? `${plan.games.length} games · ends about ${gameTime(plan.endsAt)}` : `${plan.games.length} games over ${plan.days.length} days`}
            </p>
            {overrun > 0 && <p className="form-error">⚠ Runs {overrun} min past the ideal end. Add fields, shorten games or use fewer teams.</p>}
            <ol className="gt-preview-list">
              {plan.games.map((g) => {
                const dayIndex = plan.days.findIndex((_, i) => plan.days.slice(0, i).reduce((n, d) => n + d.games, 0) === g.order && plan.days[i]!.games > 0);
                const day = plan.days.length > 1 && dayIndex >= 0 ? plan.days[dayIndex]! : null;
                return (
                  <li key={g.id}>
                    {day && (
                      <b className="gt-preview-day">
                        Day {dayIndex + 1} · {shortDay(day.startsAt)} · {day.games} games, {gameTime(day.startsAt)}–{gameTime(day.endsAt)}
                      </b>
                    )}
                    <span className="small">
                      Game {g.order + 1} · {gameTime(g.startsAt)} · Field {g.field} · {g.label}: {slotLabel(names, plan.games, g, true)} vs {slotLabel(names, plan.games, g, false)}
                      {g.ifNeeded ? " (if needed)" : ""}
                    </span>
                  </li>
                );
              })}
            </ol>
          </div>
        )}
      </section>

      <section className="card stack">
        <h3 className="card-title">Players</h3>
        {event && (
          <div className="row-card gt-rsvps">
            <span>
              <b>
                {going.length} attending · {maybe.length} planning to attend
              </b>
              <small>From the event RSVPs</small>
            </span>
            <button type="button" className="btn btn-small" disabled={going.length === 0 && maybe.length === 0} onClick={importRsvps}>
              Import
            </button>
          </div>
        )}
        <div className="gt-inline">
          <select value={adding} onChange={(e) => setAdding(e.target.value)} aria-label="Add a member">
            <option value="">{otherMembers.length ? "Add a member…" : "Every member is already in."}</option>
            {otherMembers.map((p) => (
              <option key={p.uid} value={p.uid}>
                {p.name}
              </option>
            ))}
          </select>
          <button
            type="button"
            className="btn btn-small"
            disabled={!adding}
            onClick={() => {
              const p = otherMembers.find((x) => x.uid === adding);
              if (p) setBench([...bench, p]);
              setAdding("");
            }}
          >
            Add member
          </button>
          <button type="button" className="btn btn-small btn-primary" disabled={allPlayers.length === 0 || teams.length < 2} onClick={assignTeams}>
            Assign teams
          </button>
        </div>
        <p className="muted small">Players can be added before or after the schedule is published. Pick a player to move them or make them captain.</p>
        {bench.length > 0 && (
          <div className="stack">
            <b className="small">Not on a team ({bench.length})</b>
            <div className="gt-chips">
              {bench.map((p) => (
                <PlayerChip key={p.uid} player={p} teamId={null} teams={teams} onMove={movePlayerTo} onCaptain={setCaptain} onLeaveOut={(u) => setBench(bench.filter((x) => x.uid !== u))} />
              ))}
            </div>
          </div>
        )}
        <div className="gt-teams">
          {teams.map((t) => (
            <div key={t.id} className="card gt-team-card">
              <div className="gt-inline">
                <input
                  aria-label="Team name"
                  defaultValue={t.name}
                  maxLength={groupTournamentLimits.teamName}
                  onBlur={(e) => (e.target.value.trim() ? renameTeam(t.id, e.target.value) : (e.target.value = t.name))}
                />
                <span className="muted small">({t.playerIds.length})</span>
                <button type="button" className="text-btn" disabled={teams.length <= 2} onClick={() => removeTeam(t.id)}>
                  Remove team
                </button>
              </div>
              {t.playerIds.length === 0 && <p className="muted small">No players yet.</p>}
              <div className="gt-chips">
                {t.playerIds.map((u) => (
                  <PlayerChip
                    key={u}
                    player={{ uid: u, name: t.playerNames[u] ?? "Player" }}
                    teamId={t.id}
                    captain={t.captainId === u}
                    teams={teams}
                    onMove={movePlayerTo}
                    onCaptain={setCaptain}
                    onLeaveOut={() => undefined}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>
      </section>

      <div className="card gt-bar">
        <p className="small muted">{status}</p>
        {note && <p className="small">{note}</p>}
        {error && <p className="form-error">{error}</p>}
        <div className="home-actions">
          <button type="button" className="btn" disabled={busy !== null || saveProblem !== null} onClick={() => void save()}>
            {busy === "save" ? "Saving…" : "Save"}
          </button>
          <button type="button" className="btn btn-primary" disabled={busy !== null || problem !== null} onClick={() => void publish()}>
            {busy === "publish" ? "Publishing…" : published ? "Republish schedule" : "Publish schedule"}
          </button>
        </div>
      </div>
    </form>
  );
}

function NumberField({ label, value, min, max, step = 1, onChange }: { label: string; value: number; min: number; max: number; step?: number; onChange: (v: number) => void }) {
  // Typed text is held here and only applied on blur or Enter, so clearing
  // the field mid-edit doesn't drop teams or reset a rule.
  const [text, setText] = useState<string | null>(null);
  const commit = () => {
    if (text === null) return;
    const v = Number(text);
    if (text.trim() !== "" && Number.isFinite(v)) onChange(Math.min(Math.max(Math.round(v / step) * step, min), max));
    setText(null);
  };
  return (
    <label>
      {label}
      <span className="gt-inline">
        <button type="button" className="btn btn-small" aria-label={`Fewer: ${label}`} disabled={value - step < min} onClick={() => onChange(value - step)}>
          −
        </button>
        <input
          type="number"
          value={text ?? String(value)}
          min={min}
          max={max}
          step={step}
          onChange={(e) => setText(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              commit();
            }
          }}
        />
        <button type="button" className="btn btn-small" aria-label={`More: ${label}`} disabled={value + step > max} onClick={() => onChange(value + step)}>
          +
        </button>
      </span>
    </label>
  );
}

/** A player; pick to move them, make them captain or take them out. */
function PlayerChip({
  player,
  teamId,
  captain = false,
  teams,
  onMove,
  onCaptain,
  onLeaveOut,
}: {
  player: GroupPlayer;
  teamId: string | null;
  captain?: boolean;
  teams: GroupTournamentTeam[];
  onMove: (p: GroupPlayer, to: string | null) => void;
  onCaptain: (team: string, uid: string) => void;
  onLeaveOut: (uid: string) => void;
}) {
  return (
    <label className={`gt-chip${captain ? " gt-captain" : ""}`}>
      <span>{captain ? `★ ${player.name} (C)` : player.name}</span>
      <select
        aria-label={`Move ${player.name}`}
        value=""
        onChange={(e) => {
          const v = e.target.value;
          if (v === "captain" && teamId) onCaptain(teamId, player.uid);
          else if (v === "bench") onMove(player, null);
          else if (v === "remove") onLeaveOut(player.uid);
          else if (v) onMove(player, v);
        }}
      >
        <option value="">⋯</option>
        {teamId && !captain && <option value="captain">Make captain</option>}
        {teams
          .filter((t) => t.id !== teamId)
          .map((t) => (
            <option key={t.id} value={t.id}>
              Move to {t.name}
            </option>
          ))}
        {teamId ? <option value="bench">Take off team</option> : <option value="remove">Leave out</option>}
      </select>
    </label>
  );
}

/** The suggested feed post after a first publish, public so outsiders see it too. */
function Announcement({
  teamId,
  tournamentId,
  group,
  name,
  settings: s,
  teamCount,
  event,
  onDone,
}: {
  teamId: string;
  /** Tags the post with the tournament (its follow key), as the app does. */
  tournamentId: string;
  group: Doc<TeamDoc>;
  name: string;
  settings: GroupTournamentSettings;
  teamCount: number;
  event: Doc<TeamEventDoc> | null;
  onDone: () => void;
}) {
  const { user } = useAuth();
  const day = (iso: string) => new Date(iso).toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" });
  const last = s.laterDays.at(-1);
  const suggested = `${name}: sign up to play!`;
  const [title, setTitle] = useState(suggested.length <= 100 ? suggested : name);
  const [body, setBody] = useState(
    [
      last ? `${day(s.startsAt)} to ${day(last)}, starting at ${gameTime(s.startsAt)}.` : `${day(s.startsAt)}, starting at ${gameTime(s.startsAt)}.`,
      `${groupTournamentFormatInfo[s.format].label} · ${teamCount} teams · ${s.playersOnField}v${s.playersOnField} · games to ${s.scoreCap}.`,
      event
        ? `Want to play? Join the group, then RSVP Attending on "${event.title ?? "the event"}" in Events. Teams are picked from who signs up.`
        : "Want to play? Join the group and watch Events for sign-up.",
    ].join("\n\n"),
  );
  const [location, setLocation] = useState((group as TeamDoc & { location?: { address?: string } }).location?.address ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function post(e: FormEvent) {
    e.preventDefault();
    if (!user) return;
    setBusy(true);
    setError(null);
    try {
      await callApi(user, `/v1/teams/${encodeURIComponent(teamId)}/posts`, { method: "POST", body: { title: title.trim(), body, location: location.trim(), public: true, tournamentKey: tournamentFollowKey(teamId, tournamentId) } });
      onDone();
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  return (
    <form className="card settings-form" onSubmit={(e) => void post(e)}>
      <h2 className="card-title">Tell the group</h2>
      <p className="muted small">Published. This post goes to the group feed, public so people who haven&apos;t joined see it too.</p>
      <label>
        Title
        <input value={title} maxLength={100} onChange={(e) => setTitle(e.target.value)} />
      </label>
      <label>
        Post
        <textarea rows={7} value={body} onChange={(e) => setBody(e.target.value)} />
      </label>
      <label>
        Place
        <input value={location} maxLength={200} onChange={(e) => setLocation(e.target.value)} />
      </label>
      {error && <p className="form-error">{error}</p>}
      <div className="home-actions">
        <button type="submit" className="btn btn-primary" disabled={busy}>
          Post
        </button>
        <button type="button" className="btn" onClick={onDone}>
          Skip
        </button>
      </div>
    </form>
  );
}
