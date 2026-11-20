"use client";
import Link from "next/link";
import type { CSSProperties } from "react";
import { type Doc } from "@/lib/live";
import { useAuth } from "./AuthProvider";
import { NavIcon } from "./NavIcons";
import { initials } from "@/lib/text";
import { useMyTeams } from "./useMyTeams";
import { StartOrJoinButton } from "./home/StartOrJoin";

/** Teams listed before "See all". */
const shown = 5;

/** Tile colours, picked by the team's id so a team keeps its colour. */
const tints = ["#5348b2", "#b7791f", "#2c6fb7", "#2f8f6b", "#a8407a", "#c2622d"];
export function tint(id: string) {
  let h = 0;
  for (const c of id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return tints[h % tints.length]!;
}

/** Kinds, short enough to sit beside the member count in the sidebar. */
const shortKinds: Record<string, string> = { team: "Team", community: "Community", organization: "School/club" };

/** 128, "1.2k", "12k": short enough to always fit. */
function compact(n: number) {
  return n < 1000 ? String(n) : `${(n / 1000).toFixed(n < 10_000 ? 1 : 0).replace(/\.0$/, "")}k`;
}

interface Space {
  name?: string;
  kind?: string;
  members?: Record<string, string>;
  orgId?: string | null;
  orgLinked?: boolean;
  linkedTeams?: Record<string, unknown>;
}

/**
 * The teams and groups to list, by name: as on the Teams page (MyTeams), a
 * team one of their communities lists is left out (it's reached through
 * the community).
 */
export function spacesOf<T extends Space>(all: Doc<T>[]): Doc<T>[] {
  const communities = all.filter((t) => t.kind && t.kind !== "team");
  const viaCommunity = (t: Doc<T>) =>
    t.orgLinked === true && communities.some((c) => c.id === t.orgId && Object.hasOwn(c.linkedTeams ?? {}, t.id));
  return all.filter((t) => !viaCommunity(t)).sort((a, b) => (a.name ?? "").localeCompare(b.name ?? ""));
}

/**
 * The member's teams and groups ("Your spaces") in the sidebar, each
 * labelled with its kind; "+" creates or joins one. (Home lists them in
 * its team strip where there's no sidebar list.)
 */
export function SideTeams() {
  const { user } = useAuth();
  const live = useMyTeams<Space>(user?.uid);
  if (!user || !live.data?.length) return null;
  const teams = spacesOf(live.data);
  return (
    <nav className="side-teams" aria-label="Your spaces">
      <div className="side-label-row">
        <h2 className="side-label">Your spaces</h2>
        <StartOrJoinButton className="side-add" label="Create or join a team or community">
          <NavIcon name="plus" size={16} />
        </StartOrJoinButton>
      </div>
      <div className="side-team-list">
        {teams.slice(0, shown).map((t) => {
          const count = Object.keys(t.members ?? {}).length;

          return (
            <Link
              key={t.id}
              href={`/teams/${encodeURIComponent(t.id)}`}
              className="side-team"
              style={{ "--tint": tint(t.id) } as CSSProperties}
            >
              <span className="team-tile" aria-hidden="true">
                {initials(t.name || "Team")}
              </span>
              <span>
                <b>{t.name || "Team"}</b>
                <small className="space-meta">
                  <span className="space-kind">{shortKinds[t.kind ?? "team"] ?? "Team"}</span>
                  {count > 0 && (
                    <span className="space-count" title={count === 1 ? "1 member" : `${count} members`}>
                      <NavIcon name="teams" size={12} />
                      {compact(count)}
                      <span className="sr-only">{count === 1 ? " member" : " members"}</span>
                    </span>
                  )}
                </small>
              </span>
            </Link>
          );
        })}
      </div>
      {teams.length > shown && (
        <Link href="/teams" className="side-more">
          See all {teams.length}
        </Link>
      )}
    </nav>
  );
}
