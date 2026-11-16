"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { callApi, problem } from "@/lib/client";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { NavIcon } from "../NavIcons";
import { ErrorNote, Loading } from "../StatusViews";
import { useTeamHub } from "./TeamContext";

type Kind = "team" | "community" | "organization";

/** A hub section: its path under /teams/:id, its label, and other paths that are part of it. */
export interface HubSection {
  sub: string;
  label: string;
  /** Detail pages under another path (a play under /plays) that light up this tab. */
  also?: string[];
}

/**
 * The hub's sections (spec §4) for [kind], as the tabs in a row and those
 * under More. Everyone signed in sees Feed, Schedule and the roster
 * (Members, for groups); members also get Chat, a team's Playbook, Stats
 * and Videos, and Tournaments and Meetings. Only a school or club
 * (organization) links teams, so only it has Teams (TeamSection._forKind
 * in the app). Settings is the gear beside the tabs.
 */
export function hubSections(kind: Kind, member: boolean): { tabs: HubSection[]; more: HubSection[] } {
  const feed: HubSection = { sub: "", label: "Feed" };
  const schedule: HubSection = { sub: "/schedule", label: "Schedule" };
  const chat: HubSection = { sub: "/chat", label: "Chat" };
  const roster: HubSection = { sub: "/roster", label: kind === "team" ? "Roster" : "Members" };
  const teams: HubSection = { sub: "/teams", label: "Teams" };
  const playbook: HubSection = { sub: "/playbook", label: "Playbook", also: ["/plays"] };
  const stats: HubSection = { sub: "/stats", label: "Stats" };
  const videos: HubSection = { sub: "/videos", label: "Videos" };
  const tournaments: HubSection = { sub: "/tournaments", label: "Tournaments" };
  const meetings: HubSection = { sub: "/meetings", label: "Meetings" };
  const org = kind === "organization";
  if (!member) return { tabs: [feed, schedule, roster, ...(org ? [teams] : [])], more: [] };
  if (kind === "team") return { tabs: [feed, schedule, chat, roster, playbook, stats], more: [videos, tournaments, meetings] };
  if (org) return { tabs: [feed, schedule, chat, roster, teams, tournaments], more: [meetings] };
  return { tabs: [feed, schedule, chat, roster, tournaments, meetings], more: [] };
}

/** Whether [path] is [section] of the hub at [base]. */
export function inSection(path: string, base: string, section: HubSection): boolean {
  if (!section.sub) return path === base;
  return [section.sub, ...(section.also ?? [])].some((s) => path === base + s || path.startsWith(`${base + s}/`));
}

/**
 * The hub's tabs, sticky under the top bar: up to six in a row (it
 * scrolls sideways on narrow screens, with a fade at the hidden edge),
 * then More ▾ for the rest and the Settings gear, which stay put.
 */
export function TeamNav() {
  const { teamId, kind, viewer } = useTeamHub();
  const path = usePathname();
  const base = `/teams/${teamId}`;
  const member = viewer.state === "member";
  const { tabs, more } = hubSections(kind, member);
  const scroller = useScrollEdges<HTMLElement>();
  const onSettings = path.startsWith(`${base}/settings`);

  return (
    <div className="team-tabs-bar">
      <nav ref={scroller.ref} className="team-tabs" data-edges={scroller.edges || undefined} aria-label="Team sections" onScroll={scroller.update}>
        {tabs.map((s) => {
          const active = inSection(path, base, s);
          return (
            <Link key={s.sub} href={base + s.sub} className={active ? "active" : undefined} aria-current={active ? "page" : undefined}>
              {s.label}
            </Link>
          );
        })}
      </nav>
      {more.length > 0 && <MoreMenu base={base} sections={more} path={path} />}
      {member && (
        <Link
          href={`${base}/settings`}
          className={`icon-btn team-gear${onSettings ? " on" : ""}`}
          aria-label="Settings"
          title="Settings"
          aria-current={onSettings ? "page" : undefined}
        >
          <NavIcon name="settings" size={20} />
        </Link>
      )}
    </div>
  );
}

/** Which edges of a sideways scroller hide more: "", "start", "end" or "both". */
function useScrollEdges<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [edges, setEdges] = useState("");
  const update = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    const start = el.scrollLeft > 2;
    const end = el.scrollLeft + el.clientWidth < el.scrollWidth - 2;
    setEdges(start && end ? "both" : start ? "start" : end ? "end" : "");
  }, []);
  useLayoutEffect(() => {
    update();
    const el = ref.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, [update]);
  return { ref, edges, update };
}

/** More ▾: the sections that don't fit in the row. Closes on Esc, a click outside, or opening a page. */
function MoreMenu({ base, sections, path }: { base: string; sections: HubSection[]; path: string }) {
  const [open, setOpen] = useState(false);
  const box = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const active = sections.find((s) => inSection(path, base, s));

  useEffect(() => setOpen(false), [path]);
  useEffect(() => {
    if (!open) return;
    const onDown = (e: PointerEvent) => {
      if (!box.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      setOpen(false);
      button.current?.focus();
    };
    document.addEventListener("pointerdown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <div className="team-more" ref={box}>
      <button
        ref={button}
        type="button"
        className={`team-more-button${active ? " active" : ""}`}
        aria-expanded={open}
        aria-controls="team-more-menu"
        onClick={() => setOpen((o) => !o)}
      >
        {active ? active.label : "More"} <span aria-hidden="true">▾</span>
      </button>
      {open && (
        <ul className="team-more-menu card" id="team-more-menu">
          {sections.map((s) => {
            const on = s === active;
            return (
              <li key={s.sub}>
                <Link href={base + s.sub} className={on ? "active" : undefined} aria-current={on ? "page" : undefined}>
                  {s.label}
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

/**
 * Join from the page: a community anyone may join, or ask to join one that
 * approves members. A team takes members by invite only, so its outsiders
 * get the invite-only hint (TeamBanner) instead. Members see their role
 * beside the member count (MemberCount).
 */
export function JoinButton() {
  const { teamId, kind, privateGroup, viewer } = useTeamHub();
  const { user } = useAuth();
  const request = useLiveDoc(viewer.state === "outsider" && privateGroup ? `teams/${teamId}/joinRequests/${viewer.uid}` : null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (viewer.state !== "outsider" || kind === "team" || !user) return null;

  async function run(method: string, path: string) {
    setBusy(true);
    setError(null);
    try {
      await callApi(user!, path, { method });
    } catch (e) {
      setError(problem(e));
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
  const { kind, viewer } = useTeamHub();
  // Back to this section (and its query) after logging in.
  const path = usePathname();
  // Read after mounting (useSearchParams would need a Suspense boundary here).
  const [query, setQuery] = useState("");
  useEffect(() => setQuery(window.location.search), [path]);
  if (viewer.state === "loading") return <Loading />;
  if (viewer.state === "error") {
    return (
      <div className="card hub-empty">
        <ErrorNote onRetry={() => window.location.reload()}>{viewer.message}</ErrorNote>
      </div>
    );
  }
  return (
    <div className="card hub-empty">
      <p>
        Only members see this {kind === "team" ? "team" : "group"}&apos;s {what}.
      </p>
      {viewer.state === "visitor" && (
        <Link className="btn btn-primary btn-small" href={`/sign-in?next=${encodeURIComponent(path + query)}`}>
          Log in
        </Link>
      )}
    </div>
  );
}
