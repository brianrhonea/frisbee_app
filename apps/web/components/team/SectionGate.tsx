"use client";
import type { OptionalTeamSection } from "@stall10/shared";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useTeamHub, viewerSectionOn } from "./TeamContext";

/** Settings › Sections' switches and their labels (OptionalSection in the app). */
export const optionalSectionInfo: Record<OptionalTeamSection, { label: string; description: string }> = {
  playbook: { label: "Playbook", description: "Plays drawn on a field for the team to study" },
  videos: { label: "Videos", description: "Game film and highlights, in folders" },
  stats: { label: "Stats", description: "Keep stats point by point, with season totals" },
  meetings: { label: "Meetings", description: "Video calls for the team, or some of it" },
};

/**
 * The switch a hub path follows, if any. A whole section goes with its
 * switch, except Meetings: only its list and New, so meetings already on
 * the schedule still open (the app hides only the section and New).
 */
export function sectionOfPath(path: string, base: string): OptionalTeamSection | null {
  const under = (sub: string) => path === base + sub || path.startsWith(`${base + sub}/`);
  if (under("/playbook") || under("/plays") || under("/whiteboards")) return "playbook";
  if (under("/stats")) return "stats";
  if (under("/videos")) return "videos";
  if (path === `${base}/meetings` || path === `${base}/meetings/new`) return "meetings";
  return null;
}

/**
 * Wraps the open hub section: one the owner turned off shows the app's
 * "<Section> is off" (team_section_screen.dart) instead, for members.
 * Everyone else gets the page itself (its members-only or loading view).
 */
export function SectionGate({ children }: { children: ReactNode }) {
  const { teamId, viewer } = useTeamHub();
  const path = usePathname();
  const section = sectionOfPath(path, `/teams/${teamId}`) ?? sectionOfPath(path, `/teams/${encodeURIComponent(teamId)}`);
  if (!section || viewerSectionOn(viewer, section)) return <>{children}</>;
  const label = optionalSectionInfo[section].label;
  // A league team has no switches (only its chat and members): "Not here", as the app.
  const league = viewer.state === "member" && !!viewer.team.leagueId;
  return (
    <div className="card hub-empty section-off">
      <h2 className="card-title">{league ? "Not here" : `${label} is off`}</h2>
      <p className="muted">{league ? `A team doesn't have ${label.toLowerCase()}.` : "The owner can turn it on in Settings › Sections."}</p>
    </div>
  );
}
