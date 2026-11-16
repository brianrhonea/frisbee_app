import { isYouthTeam } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { Avatar } from "@/components/Avatar";
import { ForVisitors } from "@/components/ForVisitors";
import { InviteProvider } from "@/components/team/InviteDialog";
import { InviteOnlyHint, MemberCount, TeamAbout, TeamBannerActions } from "@/components/team/TeamBanner";
import { TeamProvider } from "@/components/team/TeamContext";
import { TeamNav } from "@/components/team/TeamNav";
import { listingSubtitle } from "@/lib/site";
import { loadTeam } from "@/lib/teamPage";

type Props = { params: Promise<{ teamId: string }>; children: ReactNode };

export async function generateMetadata({ params }: Omit<Props, "children">): Promise<Metadata> {
  const { team } = await loadTeam((await params).teamId);
  const name = team.name || "A team";
  return {
    title: { default: name, template: `%s · ${name} — Stall 10` },
    description: team.description?.slice(0, 200) || `${name} on Stall 10. ${listingSubtitle(team)}`.trim(),
  };
}

/**
 * A team or group's hub (spec §4): who it is across the top (Invite for
 * member managers, the member count, a two-line description), its sections
 * as tabs, the open section below. Server-rendered from the public page,
 * so visitors and search engines see it; members get live sections. One
 * invite dialog (InviteProvider) serves the whole hub.
 */
export default async function TeamLayout({ params, children }: Props) {
  const { teamId } = await params;
  const { team } = await loadTeam(teamId);
  const name = team.name || "Team";
  const kind = team.kind ?? "team";
  const group = kind !== "team";
  // isPrivateGroup in the rules: a group that approves joins.
  const privateGroup = group && team.requiresApproval === true;
  const subtitle = listingSubtitle(team);

  return (
    <TeamProvider teamId={teamId} name={name} kind={kind} privateGroup={privateGroup} youth={isYouthTeam(team)}>
      <InviteProvider>
        <div className="page page-wide team-hub">
          <header className="team-banner">
            <Avatar name={name} size={72} />
            <div className="team-banner-text">
              <h1>{name}</h1>
              {subtitle && <p className="muted">{subtitle}</p>}
              {team.location?.address && <p className="muted small">{team.location.address}</p>}
              <MemberCount />
              {team.description && <TeamAbout text={team.description} />}
              <InviteOnlyHint />
            </div>
            <div className="team-banner-actions">
              <TeamBannerActions />
            </div>
          </header>
          <ForVisitors>
            <div className="cta-card">
              <p>{group ? "Join this group on Stall 10." : "Follow this team and keep up with its season on Stall 10."}</p>
              <Link className="btn btn-primary btn-small" href={`/sign-up?next=${encodeURIComponent(`/teams/${teamId}`)}`}>
                {group ? "Sign up to join" : "Sign up free"}
              </Link>
            </div>
          </ForVisitors>
          <TeamNav />
          <div className="team-section">{children}</div>
        </div>
      </InviteProvider>
    </TeamProvider>
  );
}
