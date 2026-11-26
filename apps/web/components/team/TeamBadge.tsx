import { TeamLogo } from "../ui/Avatar";

/** A team's or community's initials: the shared TeamLogo (ui/Avatar.tsx), kept under its old name. */
export function TeamBadge({ name, kind, size = 56 }: { name: string; kind: "team" | "community" | "organization"; size?: number }) {
  return <TeamLogo name={name} kind={kind} size={size} />;
}
