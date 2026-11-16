"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useLayoutEffect, useRef, useState } from "react";
import { Avatar } from "../Avatar";
import { FollowButton } from "../FollowButton";
import { roleLabel } from "../ProfileDashboard";
import { JoinWithCode } from "../CreateTeam";
import { Dialog } from "../Dialog";
import { ShareButton } from "../ShareButton";
import { InviteButton } from "./InviteDialog";
import { type TeamDoc, type TeamViewer, useTeamHub } from "./TeamContext";
import { JoinButton } from "./TeamNav";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

/**
 * The banner's buttons: Invite (member managers), Join (groups'
 * outsiders), Follow (people not on it, as in the app: a member's feed
 * already has every post) and Share. Members' Settings gear is the one
 * beside the tabs (TeamNav).
 */
export function TeamBannerActions() {
  const { teamId, name, viewer } = useTeamHub();
  return (
    <>
      <InviteButton />
      <JoinButton />
      {showsFollow(viewer.state) && <FollowButton type="team" targetId={teamId} />}
      <ShareButton url={new URL(`/teams/${encodeURIComponent(teamId)}`, siteUrl).toString()} title={`${name} on Stall 10`} className="btn btn-small" />
    </>
  );
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
 * How many members, with a few faces, linking to the roster, and the
 * viewer's role. Members only, as in the app (its count line): outsiders
 * can't read the team doc, and the public page doesn't say.
 */
export function MemberCount() {
  const { teamId, kind, viewer } = useTeamHub();
  if (viewer.state !== "member") return null;
  const people = membersInOrder(viewer.team);
  const n = people.length;
  return (
    <p className="member-line">
      <Link className="member-count" href={`/teams/${teamId}/roster`}>
        <span className="avatar-stack" aria-hidden="true">
          {people.slice(0, 4).map((p) => (
            <Avatar key={p.uid} name={p.name} size={24} />
          ))}
        </span>
        {n} {n === 1 ? "member" : "members"}
      </Link>
      <span className="pill">{roleLabel(viewer.tier, kind)}</span>
    </p>
  );
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
  const { teamId, kind, viewer } = useTeamHub();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  if (kind !== "team" || viewer.state !== "outsider") return null;
  return (
    <div className="invite-only">
      <span>Invite-only — have a code?</span>
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
  const { name } = useTeamHub();
  return <h1>{name}</h1>;
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
