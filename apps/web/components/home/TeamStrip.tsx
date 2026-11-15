"use client";
// Home's row of the member's teams, groups and communities under the
// composer, with New / Join at the end (the app's _TeamStrip). As in the
// sidebar (SideTeams), a team one of their communities lists is reached
// through the community.
import Link from "next/link";
import type { CSSProperties } from "react";
import { NavIcon } from "../NavIcons";
import { spacesOf, tint } from "../SideTeams";
import { useMyTeams } from "../useMyTeams";
import { initials } from "@/lib/text";
import { StartOrJoinButton } from "./StartOrJoin";

export function TeamStrip({ uid }: { uid: string }) {
  const live = useMyTeams(uid);
  if (!live.data) return null;
  const spaces = spacesOf(live.data);
  return (
    <nav className="team-strip" aria-label="Your teams and groups">
      <ul>
        {spaces.map((t) => (
          <li key={t.id}>
            <Link className="team-strip-item" href={`/teams/${encodeURIComponent(t.id)}`} style={{ "--tint": tint(t.id) } as CSSProperties}>
              <span className="team-tile" aria-hidden="true">
                {initials(t.name || "Team")}
              </span>
              <span className="team-strip-name">{t.name || "Team"}</span>
            </Link>
          </li>
        ))}
        <li>
          <StartOrJoinButton className="team-strip-item team-strip-add">
            <span className="team-tile" aria-hidden="true">
              <NavIcon name="plus" size={18} />
            </span>
            <span className="team-strip-name">{spaces.length ? "New / Join" : "Join a team"}</span>
          </StartOrJoinButton>
        </li>
      </ul>
    </nav>
  );
}
