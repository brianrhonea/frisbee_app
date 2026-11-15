"use client";
// "Needs you": people asking to join the groups the member approves
// members for (the app's Home "Needs you" card). Join requests exist only
// on groups that approve who joins, and the rules let members with Manage
// members read them, so one listener per such group (at most [maxGroups]).
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useLiveQuery } from "@/lib/live";
import { canOn } from "../tournaments/useTournament";
import { useMyTeams } from "../useMyTeams";

const maxGroups = 10;

export function NeedsYou({ uid }: { uid: string }) {
  const teams = useMyTeams(uid);
  const groups = (teams.data ?? [])
    .filter((t) => (t.kind ?? "team") !== "team" && t.requiresApproval === true && canOn(t, uid, "manageMembers"))
    .sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""))
    .slice(0, maxGroups);
  const [counts, setCounts] = useState<Record<string, number>>({});
  const onCount = useCallback((id: string, n: number) => setCounts((c) => (c[id] === n ? c : { ...c, [id]: n })), []);
  const total = groups.reduce((n, g) => n + (counts[g.id] ?? 0), 0);
  if (groups.length === 0) return null;
  return (
    <section className="card needs-you" aria-labelledby="needs-you-title" hidden={total === 0}>
      <h2 className="card-title" id="needs-you-title">
        Needs you
      </h2>
      <ul className="needs-you-list">
        {groups.map((g) => (
          <Requests key={g.id} teamId={g.id} name={g.name ?? "Group"} onCount={onCount} />
        ))}
      </ul>
    </section>
  );
}

function Requests({ teamId, name, onCount }: { teamId: string; name: string; onCount: (id: string, n: number) => void }) {
  // The same query as the group's settings (JoinRequests), so they share a listener.
  const requests = useLiveQuery<{ name?: string }>(`teams/${teamId}/joinRequests`, [], teamId);
  const n = requests.data?.length ?? 0;
  useEffect(() => onCount(teamId, n), [teamId, n, onCount]);
  if (n === 0) return null;
  return (
    <li>
      <Link href={`/teams/${encodeURIComponent(teamId)}/settings`}>
        <b>{name}</b>
        <small>{n === 1 ? "1 person is asking to join" : `${n} people are asking to join`}</small>
      </Link>
    </li>
  );
}
