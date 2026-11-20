"use client";
import { optionalTeamSections, sectionOn } from "@stall10/shared";
import Link from "next/link";
import { useEffect, useState } from "react";
import { type TeamDoc, useTeamHub } from "./TeamContext";

/** How long a team counts as brand new, for the hint (TeamHomeViewModel.newTeamFor). */
const newTeamForMs = 30 * 24 * 60 * 60 * 1000;

/**
 * Whether the owner of [team] gets the hint (showSectionsHint in the app):
 * a team (not a group or a league team) with every optional section off,
 * made under 30 days before [now] or with no time stored.
 */
export function showSectionsHint(team: TeamDoc, owner: boolean, now: Date): boolean {
  if (!owner || (team.kind ?? "team") !== "team" || team.leagueId) return false;
  if (optionalTeamSections.some((s) => sectionOn(team, s))) return false;
  const made = team.createdAt ? Date.parse(team.createdAt) : Number.NaN;
  return Number.isNaN(made) || now.getTime() - made < newTeamForMs;
}

const storageKey = (teamId: string) => `stall10.sectionsHintDismissed.${teamId}`;

/**
 * The one-time hint at the top of a brand-new team's feed, for its owner:
 * the sections it starts without are in Settings › Sections. × hides it
 * on this browser (localStorage).
 */
export function SectionsHint() {
  const { teamId, viewer } = useTeamHub();
  // Null until read from the browser, so a dismissed hint never flashes.
  const [dismissed, setDismissed] = useState<boolean | null>(null);
  useEffect(() => {
    let d = false;
    try {
      d = window.localStorage.getItem(storageKey(teamId)) === "1";
    } catch {
      // No storage: show it until dismissed on this page.
    }
    setDismissed(d);
  }, [teamId]);
  if (dismissed !== false || viewer.state !== "member") return null;
  if (!showSectionsHint(viewer.team, viewer.tier === "owner", new Date())) return null;

  function dismiss() {
    setDismissed(true);
    try {
      window.localStorage.setItem(storageKey(teamId), "1");
    } catch {
      // Hidden for this visit only.
    }
  }

  return (
    <div className="sections-hint">
      <Link href={`/teams/${encodeURIComponent(teamId)}/settings#sections`}>
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
          <path
            fill="currentColor"
            d="M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z"
          />
        </svg>
        <span>Turn on Playbook, Videos, Stats or Meetings in Settings › Sections.</span>
      </Link>
      <button type="button" className="sections-hint-close" aria-label="Dismiss" onClick={dismiss}>
        ×
      </button>
    </div>
  );
}
