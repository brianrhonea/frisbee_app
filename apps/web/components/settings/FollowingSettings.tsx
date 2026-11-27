"use client";
import { orderBy } from "firebase/firestore";
import Link from "next/link";
import { useMemo, useState } from "react";
import { callApi } from "@/lib/client";
import { type Doc, useLivePaged } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import { LoadMore } from "../LoadMore";
import { SegmentedTabs } from "../ui/SegmentedTabs";
import { ErrorNote } from "@/components/StatusViews";

/** A follow as stored (Follow in the app). */
interface Follow {
  type: "user" | "team" | "tournament";
  targetId: string;
  groupId?: string;
  name?: string;
  photoUrl?: string | null;
  notify?: boolean;
}

const tabs = [
  ["user", "Players"],
  ["team", "Teams and communities"],
  ["tournament", "Tournaments"],
] as const;

function hrefOf(f: Follow): string {
  if (f.type === "user") return `/players/${encodeURIComponent(f.targetId)}`;
  if (f.type === "team") return `/teams/${encodeURIComponent(f.targetId)}`;
  // Hosted and group tournaments store "{hostId}_{tournamentId}" with the
  // host beside it; the hosted page falls back to the group's tournament
  // (?host=), as in the app (Routes.tournament(id, host:)).
  if (f.type === "tournament" && f.groupId && f.targetId.startsWith(`${f.groupId}_`)) {
    const id = f.targetId.slice(f.groupId.length + 1);
    return `/tournaments/${encodeURIComponent(id)}?host=${encodeURIComponent(f.groupId)}`;
  }
  if (f.type === "tournament") return `/tournaments/${encodeURIComponent(f.targetId)}`;
  return "/explore#coming-up";
}

/** Everything the member follows, as a table: filter, find, notifications, unfollow. */
export function FollowingSettings() {
  const { user } = useAuth();
  // The newest follows first, a page at a time; Find and the counts cover the pages loaded.
  const paged = useLivePaged<Follow>(user ? `users/${user.uid}/follows` : null, [orderBy("createdAt", "desc")], "follows", 200);
  const { data, error } = paged;
  const [tab, setTab] = useState<Follow["type"]>("user");
  const [find, setFind] = useState("");
  const list = useMemo(() => {
    const q = find.trim().toLowerCase();
    return (data ?? []).filter((f) => f.type === tab && (!q || (f.name ?? "").toLowerCase().includes(q)));
  }, [data, tab, find]);
  if (!user) return null;
  const me = user;
  const count = (t: Follow["type"]) => (data ?? []).filter((f) => f.type === t).length;

  const patch = (f: Doc<Follow>, notify: boolean) =>
    callApi(me, `/v1/follows/${encodeURIComponent(f.id)}`, { method: "PATCH", body: { notify } });
  const unfollow = (f: Doc<Follow>) => callApi(me, `/v1/follows/${encodeURIComponent(f.id)}`, { method: "DELETE" });

  return (
    <div className="card">
      <div className="toolbar">
        <SegmentedTabs
          label="Following"
          items={tabs.map(([id, label]) => ({ id, label: `${label} ${count(id)}` }))}
          value={tab}
          onChange={(t) => setTab(t as Follow["type"])}
        />
        <span className="composer-spacer" />
        <input className="search-input" type="search" placeholder="Find" value={find} onChange={(e) => setFind(e.target.value)} />
      </div>
      {error && <ErrorNote>{error}</ErrorNote>}
      {data === undefined && !error && <p className="muted">Loading…</p>}
      {data && list.length === 0 && (
        <p className="empty">
          {find ? "No matches." : <>Nothing here yet. <Link href="/explore">Find people and teams to follow</Link>.</>}
        </p>
      )}
      {list.length > 0 && (
        <table className="data-table">
          <thead>
            <tr>
              <th>Name</th>
              <th className="narrow">Notify me</th>
              <th className="narrow" />
            </tr>
          </thead>
          <tbody>
            {list.map((f) => (
              <tr key={f.id}>
                <td>
                  <Link href={hrefOf(f)} className="row-link">
                    <Avatar name={f.name || "?"} url={f.photoUrl ?? undefined} size={30} />
                    {f.name || f.targetId}
                  </Link>
                </td>
                <td className="narrow">
                  <input
                    type="checkbox"
                    role="switch"
                    aria-label={`Notify me about ${f.name}`}
                    checked={f.notify === true}
                    onChange={(e) => void patch(f, e.target.checked).catch(() => undefined)}
                  />
                </td>
                <td className="narrow">
                  <button type="button" className="btn btn-small" onClick={() => void unfollow(f).catch(() => undefined)}>
                    Unfollow
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <LoadMore paged={paged} label="Show more follows" />
    </div>
  );
}
