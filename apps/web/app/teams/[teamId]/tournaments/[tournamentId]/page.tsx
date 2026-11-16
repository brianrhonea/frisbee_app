import type { Metadata } from "next";
import type { PublicGroupTournament } from "@stall10/shared";
import { GroupTournamentPage } from "@/components/team/group_tournaments/GroupTournamentPage";
import { getPublicOrNull } from "@/lib/api";

export const metadata: Metadata = { title: "Tournament" };

type Props = { params: Promise<{ teamId: string; tournamentId: string }> };

/** A group tournament. Visitors get its public listing (none for a private group); members get the live page. */
export default async function GroupTournamentRoute({ params }: Props) {
  const { teamId, tournamentId } = await params;
  let listing: PublicGroupTournament | null = null;
  try {
    listing = await getPublicOrNull<PublicGroupTournament>(`/v1/public/group-tournaments/${encodeURIComponent(teamId)}/${encodeURIComponent(tournamentId)}`);
  } catch {
    // Members still get the live page; visitors the members-only prompt.
  }
  return <GroupTournamentPage tournamentId={tournamentId} publicListing={listing} />;
}
