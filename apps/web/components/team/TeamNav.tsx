"use client";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { ApiError, callApi } from "@/lib/client";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { roleLabel } from "../ProfileDashboard";
import { useTeamHub } from "./TeamContext";

/** More's parts (TeamMore's ?tab=), shown as tabs of their own on desktops. */
export const moreTabs = {
  team: [
    ["playbook", "Playbook"],
    ["videos", "Videos"],
    ["stats", "Stats"],
    ["tournaments", "Tournaments"],
  ],
  community: [["tournaments", "Tournaments"]],
} as const satisfies Record<string, ReadonlyArray<readonly [string, string]>>;

/**
 * The hub's sections (spec §4): Feed, Schedule and Roster for everyone
 * signed in; Chat and More once the viewer is a member. A community calls
 * its roster Members, lists its teams under Teams, and keeps no playbook,
 * videos or stats. Desktops have room for More's parts as tabs of their
 * own; narrower screens keep them under More.
 */
export function TeamNav() {
  return (
    // useSearchParams needs a Suspense boundary; until it resolves, no tab under More is marked.
    <Suspense fallback={<Tabs moreTab={null} />}>
      <TabsWithParams />
    </Suspense>
  );
}

function TabsWithParams() {
  return <Tabs moreTab={useSearchParams().get("tab")} />;
}

function Tabs({ moreTab }: { moreTab: string | null }) {
  const { teamId, kind, viewer } = useTeamHub();
  const path = usePathname();
  const base = `/teams/${teamId}`;
  const member = viewer.state === "member";
  const parts = kind === "team" ? moreTabs.team : moreTabs.community;
  const onMore = path.startsWith(`${base}/more`);
  const shownPart = parts.find(([k]) => k === moreTab)?.[0] ?? parts[0][0];
  const sections: Array<[string, string, boolean]> = [
    ["", "Feed", true],
    ["/schedule", "Schedule", true],
    ["/chat", "Chat", member],
    ["/roster", kind === "team" ? "Roster" : "Members", true],
    ["/teams", "Teams", kind !== "team"],
  ];
  const tab = (href: string, label: string, active: boolean, className = "") => (
    <Link
      key={href}
      href={href}
      className={[className, active ? "active" : ""].filter(Boolean).join(" ") || undefined}
      aria-current={active ? "page" : undefined}
    >
      {label}
    </Link>
  );
  return (
    <nav className="team-tabs" aria-label="Team sections">
      {sections
        .filter(([, , shown]) => shown)
        .map(([sub, label]) => {
          const href = base + sub;
          return tab(href, label, sub ? path.startsWith(href) : path === base);
        })}
      {member && (
        <>
          {parts.map(([k, label]) => tab(`${base}/more?tab=${k}`, label, onMore && shownPart === k, "wide-only"))}
          {tab(`${base}/more`, kind === "team" ? "More" : "Tournaments", onMore, "narrow-only")}
        </>
      )}
    </nav>
  );
}

/**
 * Join from the page: a community anyone may join, or ask to join one that
 * approves members. A team takes members by invite only, so outsiders follow
 * it instead. Members see their role.
 */
export function JoinButton() {
  const { teamId, kind, privateGroup, viewer } = useTeamHub();
  const { user } = useAuth();
  const request = useLiveDoc(viewer.state === "outsider" && privateGroup ? `teams/${teamId}/joinRequests/${viewer.uid}` : null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (viewer.state === "member") return <span className="pill">{roleLabel(viewer.tier, kind)}</span>;
  if (viewer.state !== "outsider" || kind === "team" || !user) return null;

  async function run(method: string, path: string) {
    setBusy(true);
    setError(null);
    try {
      await callApi(user!, path, { method });
    } catch (e) {
      setError(e instanceof ApiError ? e.message : "Something went wrong. Try again.");
    } finally {
      setBusy(false);
    }
  }

  let button;
  if (!privateGroup) {
    button = (
      <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={() => void run("POST", `/v1/teams/${teamId}/members`)}>
        Join
      </button>
    );
  } else if (request.data) {
    button = (
      <button
        type="button"
        className="btn btn-small"
        title="Take back your request"
        disabled={busy}
        onClick={() => void run("DELETE", `/v1/teams/${teamId}/join-requests/${viewer.uid}`)}
      >
        Requested
      </button>
    );
  } else {
    button = (
      <button
        type="button"
        className="btn btn-primary btn-small"
        disabled={busy || request.data === undefined}
        onClick={() => void run("POST", `/v1/teams/${teamId}/join-requests`)}
      >
        Ask to join
      </button>
    );
  }
  return (
    <span className="follow">
      {button}
      {error && <span className="post-error">{error}</span>}
    </span>
  );
}

/** Shown in a members-only section to anyone who isn't one. */
export function MembersOnlySection({ what }: { what: string }) {
  const { teamId, viewer } = useTeamHub();
  if (viewer.state === "loading") return <p className="muted" aria-busy="true">Loading…</p>;
  return (
    <div className="card hub-empty">
      <p>Only members see this team&apos;s {what}.</p>
      {viewer.state === "visitor" && (
        <Link className="btn btn-primary btn-small" href={`/sign-in?next=${encodeURIComponent(`/teams/${teamId}`)}`}>
          Log in
        </Link>
      )}
    </div>
  );
}
