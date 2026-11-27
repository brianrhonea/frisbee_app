"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useLayoutEffect, useRef, useState } from "react";
import { AvatarStack } from "../ui/Avatar";
import { FollowButton } from "../FollowButton";
import { roleLabel } from "../ProfileDashboard";
import { JoinWithCode } from "../CreateTeam";
import { Dialog } from "../Dialog";
import { NavIcon } from "../NavIcons";
import { ShareButton } from "../ShareButton";
import { InviteButton } from "./InviteDialog";
import { MessageStaff } from "./MessageStaff";
import { TeamBadge } from "./TeamBadge";
import { type TeamDoc, type TeamViewer, useTeamHub } from "./TeamContext";
import { JoinButton } from "./TeamNav";
import { StatusPill } from "../ui/StatusPill";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

/**
 * The header's buttons, as the app's compact team header: Invite (member
 * managers; turf, with an amber count of join requests), Join (groups'
 * outsiders), Follow (people not on it, as in the app: a member's feed
 * already has every post), Message (members: the team chat and the staff; signed-in outsiders: the staff), Share, and
 * members' Settings gear.
 */
export function TeamBannerActions() {
  const { teamId, name, viewer } = useTeamHub();
  const path = usePathname();
  const base = `/teams/${teamId}`;
  const member = viewer.state === "member";
  const onSettings = path.startsWith(`${base}/settings`);
  return (
    <>
      <InviteButton />
      <JoinButton />
      {showsFollow(viewer.state) && <FollowButton type="team" targetId={teamId} />}
      <MessageStaff />
      <ShareButton url={new URL(`/teams/${encodeURIComponent(teamId)}`, siteUrl).toString()} title={`${name} on Stall 10`} className="btn btn-small btn-quiet" />
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
    </>
  );
}

/** The header's initials badge, for the name members see (TeamName). */
export function TeamHeadBadge({ size = 56 }: { size?: number }) {
  const { name, kind } = useTeamHub();
  return <TeamBadge name={name} kind={kind} size={size} />;
}

/** Whether the banner offers Follow: only once the viewer is known not to be on the team (the app's TeamHomeViewModel.follow). */
export const showsFollow = (state: TeamViewer["state"]): boolean => state === "outsider" || state === "visitor";

/** The first members by tier then name, as the app's member card lists them. */
export function membersInOrder(team: TeamDoc): Array<{ uid: string; name: string; tier: string }> {
  const rank = ["owner", "coach", "captain", "stats", "player"];
  const tierRank = (t: string) => (rank.indexOf(t) < 0 ? rank.length : rank.indexOf(t));
  return (team.memberIds ?? [])
    .map((uid) => ({ uid, name: team.memberNames?.[uid] || "Member", tier: team.members?.[uid] ?? "player" }))
    .sort((a, b) => tierRank(a.tier) - tierRank(b.tier) || a.name.localeCompare(b.name));
}

/**
 * The meta line under the name (the app's _metaLine): what the team is and
 * where ([subtitle]), then for members how many are on it, with a few
 * faces, linking to the roster, the year it started and the viewer's role.
 * Members only past the subtitle, as in the app: outsiders can't read the
 * team doc, and the public page doesn't say.
 */
export function TeamMeta({ subtitle }: { subtitle?: string }) {
  const { teamId, kind, viewer } = useTeamHub();
  const member = viewer.state === "member" ? viewer : null;
  const people = member ? membersInOrder(member.team) : [];
  const n = people.length;
  const created = member?.team.createdAt ? new Date(member.team.createdAt) : null;
  const founded = created && !Number.isNaN(created.getTime()) ? created.getFullYear() : null;
  if (!subtitle && !member) return null;
  return (
    <p className="team-meta member-line">
      {subtitle && <span>{subtitle}</span>}
      {member && (
        <Link className="member-count" href={`/teams/${teamId}/roster`}>
          <AvatarStack people={people.map((p) => ({ id: p.uid, name: p.name }))} max={4} size={20} />
          {n} {n === 1 ? "member" : "members"}
        </Link>
      )}
      {founded && <span>Est. {founded}</span>}
      {member && <StatusPill tone="accent">{roleLabel(member.tier, kind)}</StatusPill>}
    </p>
  );
}

/** How many members and the viewer's role: the meta line without a subtitle. */
export function MemberCount() {
  return <TeamMeta />;
}

/** The description, two lines until "more". */
export function TeamAbout({ text }: { text: string }) {
  const ref = useRef<HTMLParagraphElement>(null);
  const [open, setOpen] = useState(false);
  const [long, setLong] = useState(false);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el || open) return;
    const measure = () => setLong(el.scrollHeight > el.clientHeight + 1);
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [open, text]);
  return (
    <div className="team-about-wrap">
      <p ref={ref} id="team-about" className={`team-about${open ? "" : " clamped"}`}>
        {text}
      </p>
      {(long || open) && (
        <button type="button" className="text-btn" aria-expanded={open} aria-controls="team-about" onClick={() => setOpen((o) => !o)}>
          {open ? "less" : "more"}
        </button>
      )}
    </div>
  );
}

/**
 * A team takes members by invite only (the API refuses Join), so someone
 * signed in who isn't on it is told so and can type in a code or link.
 */
export function InviteOnlyHint() {
  const { teamId, kind, joinRequests, viewer } = useTeamHub();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  if (kind !== "team" || viewer.state !== "outsider") return null;
  return (
    <div className="invite-only">
      <span>{joinRequests ? "Ask to join, or have a code?" : "Invite-only — have a code?"}</span>
      <button type="button" className="btn btn-small" onClick={() => setOpen(true)}>
        Join with a code
      </button>
      {open && (
        <Dialog label="Join with a code" onClose={() => setOpen(false)} dismissOnBackdrop>
          <JoinWithCode
            onCancel={() => setOpen(false)}
            onJoined={(joined) => {
              // This team: reload, so the page listens again as a member.
              if (joined === teamId) window.location.reload();
              else router.push(`/teams/${encodeURIComponent(joined)}`);
            }}
          />
        </Dialog>
      )}
    </div>
  );
}

/**
 * The hub's name: the public listing's, or for members the team doc's
 * (a drafted league team's real name is hidden from everyone else).
 */
export function TeamName() {
  return <h1>{<TeamNameText />}</h1>;
}

/** The same name as plain text, for a heading something else draws (the cover header). */
export function TeamNameText() {
  const { name } = useTeamHub();
  return <>{name}</>;
}

/**
 * The listing's address, or for members the team doc's (the public page
 * leaves a youth team's out).
 */
export function TeamAddress({ address }: { address?: string }) {
  const { viewer } = useTeamHub();
  const shown = viewer.state === "member" ? (viewer.team.location?.address ?? address) : address;
  return shown ? <p className="muted small">{shown}</p> : null;
}
