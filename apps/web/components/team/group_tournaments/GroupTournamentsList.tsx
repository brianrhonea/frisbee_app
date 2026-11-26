"use client";
import { type GroupTournamentDoc, groupTournamentFormatInfo, groupTournamentStatusLabels } from "@stall10/shared";
import { where } from "firebase/firestore";
import Link from "next/link";
import { DateTile } from "../DateTile";
import { useLiveQuery } from "@/lib/live";
import { useTeamHub } from "../TeamContext";
import { tournamentView, tournamentWhen } from "./format";
import "./group_tournaments.css";
import { StatusPill } from "../../ui/StatusPill";

/**
 * A group's own (hat) tournaments, in its Tournaments section
 * (HatTournamentsList in the app). Organizers (manageEvents) see every one
 * and set them up; members see the ones they play in, which is what the
 * rules let them ask for.
 */
export function GroupTournamentsList() {
  const { teamId, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const organizer = member?.can("manageEvents") ?? false;
  const list = useLiveQuery<GroupTournamentDoc>(
    member ? `teams/${teamId}/groupTournaments` : null,
    organizer || !member ? [] : [where("participantIds", "array-contains", member.uid)],
    organizer ? "all" : (member?.uid ?? ""),
  );
  const base = `/teams/${encodeURIComponent(teamId)}/tournaments`;
  const rows = (list.data ?? []).map(tournamentView).sort((a, b) => b.settings.startsAt.localeCompare(a.settings.startsAt));

  return (
    <section className="stack">
      <div className="gt-head">
        <h2 className="card-title">Hat tournaments</h2>
        {organizer && (
          <Link href={`${base}/new`} className="btn btn-primary btn-small">
            New tournament
          </Link>
        )}
      </div>
      {list.error && <p className="form-error">{list.error}</p>}
      {!list.error && !list.data && (
        <p className="muted" aria-busy="true">
          Loading…
        </p>
      )}
      {list.data && rows.length === 0 && (
        <p className="empty">
          {organizer
            ? "Teams made from who RSVPs to a Tournament event: import who's coming, make teams and generate the schedule."
            : "No tournaments here that you're playing in."}
        </p>
      )}
      {rows.map((t) => (
        <Link
          key={t.id}
          className="row-card gt-list-row"
          href={t.status === "setup" && organizer ? `${base}/${encodeURIComponent(t.id)}/edit` : `${base}/${encodeURIComponent(t.id)}`}
        >
          <DateTile startsAt={t.settings.startsAt} />
          <span>
            <b>{t.name || "Tournament"}</b>
            <small>
              {tournamentWhen(t.settings.startsAt)} · {groupTournamentFormatInfo[t.settings.format].label} · {t.teams.length} teams
            </small>
          </span>
          <StatusPill tone={t.status === "scheduled" ? "accent" : "neutral"}>{groupTournamentStatusLabels[t.status]}</StatusPill>
        </Link>
      ))}
    </section>
  );
}
