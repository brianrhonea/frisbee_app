"use client";
// Finding hosted tournaments and leagues: upcoming ones anyone signed in
// can find (FindTournamentsScreen), a host's own list on its hub with what
// a team plays in (HostedTournamentsSection). Picking who hosts a new one
// (HostEventScreen) is HostEvent.tsx.
import {
  type EnteredTournamentDoc,
  entryStatusLabels,
  feeLabel,
  type HostedStatus,
  hostedStatuses,
  hostedStatusLabels,
  hostedType,
  type HostedType,
  hostedTypeLabels,
  publishedStatuses,
  spotsLabel,
  type TournamentDoc,
  type TournamentSpots,
  divisionLabel,
} from "@stall10/shared";
import { limit, orderBy, where } from "firebase/firestore";
import Link from "next/link";
import { useMemo, useState } from "react";
import { useAuth } from "@/components/AuthProvider";
import { type Doc, useLiveQuery } from "@/lib/live";
import "./tournaments.css";
import { useTournamentSpots } from "./useTournamentSpots";
import { formatDate, startOfToday } from "@/lib/dates";
import { dayKey, localeFor, useRenderZone } from "@/lib/renderZone";

export const tournamentHref = (id: string) => `/tournaments/${encodeURIComponent(id)}`;

const dayFmt = (iso: string | null | undefined, opts: Intl.DateTimeFormatOptions = { month: "short", day: "numeric" }, zone?: string) =>
  iso ? formatDate(iso, { ...opts, timeZone: zone }, localeFor(zone)) : "";

/** "Jun 6 – 7, 2026" or "Jun 6, 2026" (hostedDates), in [zone] (useRenderZone), else the viewer's. */
export function datesLabel(startsOn: string | null | undefined, endsOn: string | null | undefined, zone?: string): string {
  if (!startsOn) return "";
  const s = new Date(startsOn);
  const e = endsOn ? new Date(endsOn) : null;
  const year: Intl.DateTimeFormatOptions = { month: "short", day: "numeric", year: "numeric" };
  if (!e || dayKey(e, zone) === dayKey(s, zone)) return dayFmt(startsOn, year, zone);
  return `${dayFmt(startsOn, undefined, zone)} – ${dayFmt(endsOn, year, zone)}`;
}

/** What a list card shows: a member's live document, or a visitor's public card (PublicHostedCard). */
export type CardTournament = Pick<
  Doc<TournamentDoc>,
  "id" | "name" | "hostName" | "hostOfficial" | "kind" | "entryType" | "teamEntry" | "divisions" | "visibility" | "startsOn" | "endsOn" | "location" | "status"
> & {
  bidFee: { amountCents: number; currency: string } | null;
  /** A visitor's public card carries its spots left (PublicHostedCard.spots); members' come from useTournamentSpots. */
  spots?: TournamentSpots;
};

/**
 * "3 spots left" while registration is open: turf while there's room,
 * neutral "Full · waitlist" once there isn't (never amber: that's only
 * the viewer's own to-dos).
 */
export function SpotsLeft({ spots }: { spots: TournamentSpots }) {
  return <small className={`spots-left${spots.left <= 0 ? " spots-full" : ""}`}>{spotsLabel(spots)}</small>;
}

export function StatusBadge({ status }: { status: HostedStatus }) {
  return <span className={`pill hosted-status hosted-${status}`}>{hostedStatusLabels[status] ?? status}</span>;
}

/** The first day as a date tile (month over the day number), in [zone]. */
function DateTile({ iso, zone }: { iso: string | null | undefined; zone?: string }) {
  return (
    <span className="event-date" aria-hidden="true">
      {iso ? (
        <>
          <small>{dayFmt(iso, { month: "short" }, zone)}</small>
          <b>{dayFmt(iso, { day: "numeric" }, zone)}</b>
        </>
      ) : (
        <b>–</b>
      )}
    </span>
  );
}

/** One tournament in a list (HostedTournamentCard). */
export function TournamentCard({ t, showHost = true }: { t: CardTournament; showHost?: boolean }) {
  const zone = useRenderZone();
  const fetched = useTournamentSpots();
  const spots = t.spots ?? fetched.get(t.id);
  const type = hostedType(t);
  const fee = t.bidFee;
  const meta = [
    type !== "tournament" ? hostedTypeLabels[type] : null,
    showHost ? t.hostName : null,
    t.divisions?.length ? t.divisions.map(divisionLabel).join(", ") : null,
    t.visibility === "inviteOnly" ? "Invite only" : null,
    fee ? `${feeLabel(fee)} ${t.entryType === "players" ? "to play" : "bid"}` : null,
  ].filter(Boolean);
  return (
    <Link href={tournamentHref(t.id)} className="row-card">
      <DateTile iso={t.startsOn} zone={zone} />
      <span>
        <b>
          {t.name || "Tournament"}
          {t.hostOfficial ? <span className="hosted-official"> Official</span> : null}
        </b>
        <small>{[datesLabel(t.startsOn, t.endsOn, zone), t.location].filter(Boolean).join(" · ")}</small>
        {meta.length > 0 && <small>{meta.join(" · ")}</small>}
        {spots && t.status === "registration" && <SpotsLeft spots={spots} />}
      </span>
      <StatusBadge status={t.status} />
    </Link>
  );
}

/** "All" and each status (or kind) the list has, when there's more than one. */
function Filters<K extends string>({ counts, labels, value, onChange, label }: { counts: Map<K, number>; labels: Record<K, string>; value: K | null; onChange: (v: K | null) => void; label: string }) {
  if (counts.size < 2) return null;
  const total = [...counts.values()].reduce((a, b) => a + b, 0);
  return (
    <div className="segmented hosted-filters" role="group" aria-label={label}>
      <button type="button" className={value === null ? "on" : ""} onClick={() => onChange(null)}>
        All ({total})
      </button>
      {[...counts.entries()].map(([k, n]) => (
        <button key={k} type="button" className={value === k ? "on" : ""} onClick={() => onChange(k)}>
          {labels[k]} ({n})
        </button>
      ))}
    </div>
  );
}

/** Narrows [list] by a search, a kind and a status, as HostedTournamentsViewModel does. */
function useFiltered<T extends CardTournament>(list: T[]) {
  const [query, setQuery] = useState("");
  const [type, setType] = useState<HostedType | null>(null);
  const [status, setStatus] = useState<HostedStatus | null>(null);
  const typeCounts = new Map<HostedType, number>();
  for (const t of list) typeCounts.set(hostedType(t), (typeCounts.get(hostedType(t)) ?? 0) + 1);
  const byType = typeCounts.size > 1 && type ? list.filter((t) => hostedType(t) === type) : list;
  const q = query.trim().toLowerCase();
  const matching = byType.filter((t) => !q || `${t.name} ${t.hostName} ${t.location} ${hostedTypeLabels[hostedType(t)]}`.toLowerCase().includes(q));
  const statusCounts = new Map<HostedStatus, number>();
  for (const s of hostedStatuses) {
    const n = matching.filter((t) => t.status === s).length;
    if (n) statusCounts.set(s, n);
  }
  const shown = statusCounts.size > 1 && status ? matching.filter((t) => t.status === status) : matching;
  return { query, setQuery, type, setType, typeCounts, status, setStatus, statusCounts, shown };
}

const openStatuses: HostedStatus[] = ["registration", "seeding", "scheduled", "live"];

/**
 * Upcoming published tournaments and leagues, soonest first, at most
 * [max] (watchUpcoming): ones starting from a week ago on, plus leagues
 * still running. Find tournaments and Explore read it.
 */
export function useUpcomingTournaments(max = 50) {
  const { user } = useAuth();
  const [since] = useState(startOfToday);
  const weekAgo = new Date(since.getFullYear(), since.getMonth(), since.getDate() - 7);
  const starting = useLiveQuery<TournamentDoc>(
    user ? "tournaments" : null,
    [where("status", "in", openStatuses), where("startsOn", ">=", weekAgo), orderBy("startsOn"), limit(max)],
    `start${since.getTime()}:${max}`,
  );
  // A league that began weeks ago still runs until its last night.
  const running = useLiveQuery<TournamentDoc>(
    user ? "tournaments" : null,
    [where("status", "in", openStatuses), where("endsOn", ">=", since), orderBy("endsOn"), limit(max)],
    `run${since.getTime()}:${max}`,
  );
  const list = useMemo(() => {
    const byId = new Map<string, Doc<TournamentDoc>>();
    for (const t of [...(starting.data ?? []), ...(running.data ?? [])]) byId.set(t.id, t);
    return [...byId.values()].sort((a, b) => a.startsOn.localeCompare(b.startsOn)).slice(0, max);
  }, [starting.data, running.data, max]);
  // Without its index yet, the running query fails; the first still lists everything else.
  return { list: starting.data ? list : undefined, error: starting.error };
}

/** Upcoming published tournaments and leagues, soonest first (FindTournamentsScreen), live for members. */
export function FindTournaments() {
  const upcoming = useUpcomingTournaments();
  if (upcoming.error) return <p className="form-error">{upcoming.error}</p>;
  if (!upcoming.list) return <p className="muted" aria-busy="true">Loading…</p>;
  return <TournamentFinder list={upcoming.list} />;
}

/**
 * The list with its search and filters. Visitors ([visitor], from
 * `/v1/public/tournaments`) don't get Host an event; sign-up links come back to [visitor].next.
 */
export function TournamentFinder({ list, visitor }: { list: CardTournament[]; visitor?: { next: string } }) {
  const f = useFiltered(list);
  const q = visitor ? `?next=${encodeURIComponent(visitor.next)}` : "";
  return (
    <div className="stack">
      <div className="hosted-toolbar">
        <input className="search-input" type="search" placeholder="Search by name, host or place" value={f.query} onChange={(e) => f.setQuery(e.target.value)} aria-label="Search tournaments" />
        {!visitor && (
          <Link className="btn btn-primary btn-small" href="/tournaments/host">
            Host an event
          </Link>
        )}
      </div>
      <Filters counts={f.typeCounts} labels={hostedTypeLabels} value={f.type} onChange={f.setType} label="Kind" />
      <Filters counts={f.statusCounts} labels={hostedStatusLabels} value={f.status} onChange={f.setStatus} label="Status" />
      {f.shown.length === 0 ? (
        <p className="empty">
          No upcoming events. Groups and schools or clubs host tournaments, hat tournaments and leagues.{" "}
          <Link href={visitor ? `/sign-up${q}` : "/tournaments/host"}>Host one</Link>.
        </p>
      ) : (
        f.shown.map((t) => <TournamentCard key={t.id} t={t} />)
      )}
    </div>
  );
}

/**
 * A host's tournaments and leagues, for its hub's Tournaments tab: drafts
 * too for its event managers, and for a team's members what the team
 * plays in.
 */
export function HostedTournamentsSection({ teamId, kind, manager, member }: { teamId: string; kind: "team" | "community" | "organization"; manager: boolean; member: boolean }) {
  const { user } = useAuth();
  // Drafts are only readable by managers, so others ask for published ones.
  const hosted = useLiveQuery<TournamentDoc>(
    user ? "tournaments" : null,
    manager ? [where("hostId", "==", teamId)] : [where("hostId", "==", teamId), where("status", "in", publishedStatuses)],
    `${teamId}:${manager}`,
  );
  const entered = useLiveQuery<EnteredTournamentDoc>(user && member && kind === "team" ? `teams/${teamId}/tournamentEntries` : null, [], teamId);
  const playing = (entered.data ?? [])
    .filter((e) => ["accepted", "invited", "applied", "waitlisted"].includes(e.status))
    .sort((a, b) => (a.startsOn ?? "~").localeCompare(b.startsOn ?? "~"));
  const list = useMemo(() => [...(hosted.data ?? [])].sort((a, b) => b.startsOn.localeCompare(a.startsOn)), [hosted.data]);
  const f = useFiltered(list);

  return (
    <div className="stack">
      {playing.length > 0 && (
        <>
          <h3 className="hosted-heading">Playing in</h3>
          {playing.map((e) => (
            <Link key={e.id} href={tournamentHref(e.id)} className="row-card">
              <span>
                <b>{e.name || "Tournament"}</b>
                <small>{[datesLabel(e.startsOn, e.endsOn), e.location, e.hostName ? `Hosted by ${e.hostName}` : ""].filter(Boolean).join(" · ")}</small>
              </span>
              <span className={`pill${e.status === "accepted" ? " hosted-live" : ""}`}>{entryStatusLabels[e.status]}</span>
            </Link>
          ))}
          {(list.length > 0 || manager) && <h3 className="hosted-heading">Hosted here</h3>}
        </>
      )}
      <div className="home-actions hosted-actions">
        {manager && (
          <Link className="btn btn-primary btn-small" href="/tournaments/host">
            Host an event
          </Link>
        )}
        <Link className="btn btn-small" href="/tournaments">
          Find tournaments and leagues
        </Link>
      </div>
      <Filters counts={f.statusCounts} labels={hostedStatusLabels} value={f.status} onChange={f.setStatus} label="Status" />
      {hosted.error ? (
        <p className="form-error">{hosted.error}</p>
      ) : !hosted.data ? (
        <p className="muted" aria-busy="true">Loading…</p>
      ) : f.shown.length === 0 ? (
        <p className="empty">
          {manager
            ? "Host a tournament, a hat tournament or a league. Pick divisions, set a fee, take applications or player signups, then publish the schedule."
            : "No tournaments or leagues hosted here yet."}
        </p>
      ) : (
        f.shown.map((t) => <TournamentCard key={t.id} t={t} showHost={false} />)
      )}
    </div>
  );
}
