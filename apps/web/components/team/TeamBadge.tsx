import { initials } from "@/lib/text";

/**
 * A team's or community's initials (TeamInitials in the app): a rounded
 * square in team blue for a team, a turf circle for a pickup community and
 * a navy circle for a school or club.
 */
export function TeamBadge({ name, kind, size = 56 }: { name: string; kind: "team" | "community" | "organization"; size?: number }) {
  return (
    <span className={`team-badge ${kind}`} aria-hidden="true" style={{ width: size, height: size, fontSize: size * 0.45 }}>
      {initials(name || "Team", 2)}
    </span>
  );
}
