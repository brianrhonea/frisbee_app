"use client";
import Link from "next/link";
import { useAuth } from "../AuthProvider";

/**
 * Back to the Teams list from a hub, for members (as the app's "All
 * teams" back button): invitations, finding and starting teams.
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
