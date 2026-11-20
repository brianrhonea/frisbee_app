import { isYouthTeam, publicPageOn, rosterIsPublic } from "@stall10/shared";
import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { AllTeamsLink } from "@/components/team/AllTeamsLink";
import { ForVisitors } from "@/components/ForVisitors";
import { InviteProvider } from "@/components/team/InviteDialog";
import { SectionGate } from "@/components/team/SectionGate";
import { InviteOnlyHint, TeamAbout, TeamAddress, TeamBannerActions, TeamHeadBadge, TeamMeta, TeamName } from "@/components/team/TeamBanner";
import { TeamProvider } from "@/components/team/TeamContext";
import { TeamNav } from "@/components/team/TeamNav";
import { listingSubtitle } from "@/lib/site";
import { loadTeam } from "@/lib/teamPage";
import "@/components/team/team_hub.css";

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
 * A team or group's hub (spec §4): a compact header as in the app (the
 * initials badge, the name, a meta line with the member count, a two-line
 * description; Invite for member managers, Message, Settings), its
 * sections as tabs, the open section below. Server-rendered from the public page,
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
  // A team whose "Public team page" is off (publicPageOn): its card only.
  const privatePage = !group && !publicPageOn(team);
  const subtitle = listingSubtitle(team);

  return (
    <TeamProvider teamId={teamId} name={name} kind={kind} privateGroup={privateGroup} privatePage={privatePage} youth={isYouthTeam(team)} publicRoster={rosterIsPublic(team)}>
      <InviteProvider>
        <div className="page page-wide team-hub">
          <AllTeamsLink />
          <header className="team-banner team-head">
            <TeamHeadBadge />
            <div className="team-banner-text">
              <TeamName />
              <TeamMeta subtitle={subtitle} />
              <TeamAddress address={team.location?.address} />
              {team.description && <TeamAbout text={team.description} />}
              <InviteOnlyHint />
            </div>
            <div className="team-banner-actions">
              <TeamBannerActions />
            </div>
          </header>
          <ForVisitors>
            <div className="cta-card">
              <p>{group ? "Join this community on Stall 10." : "Follow this team and keep up with its season on Stall 10."}</p>
              <Link className="btn btn-primary btn-small" href={`/sign-up?next=${encodeURIComponent(`/teams/${teamId}`)}`}>
                {group ? "Sign up to join" : "Sign up free"}
              </Link>
            </div>
          </ForVisitors>
          <TeamNav />
          <div className="team-section">
            <SectionGate>{children}</SectionGate>
          </div>
        </div>
      </InviteProvider>
    </TeamProvider>
  );
}
