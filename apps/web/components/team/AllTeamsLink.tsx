"use client";
import Link from "next/link";
import { useAuth } from "../AuthProvider";

/**
 * Back to the Teams list from a hub, for members: a member on only one
 * team or community gets its hub straight from the Teams tab, so this is
 * their way to the list (invitations, finding and starting teams).
 */
export function AllTeamsLink() {
  const { user } = useAuth();
  if (!user) return null;
  return (
    <nav aria-label="Breadcrumb" className="team-back">
      <Link href="/teams">‹ All teams</Link>
    </nav>
  );
}
