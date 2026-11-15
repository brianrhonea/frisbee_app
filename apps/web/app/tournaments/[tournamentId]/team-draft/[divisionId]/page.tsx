import { redirect } from "next/navigation";

type Props = { params: Promise<{ tournamentId: string; divisionId: string }> };

/** The old address of the host's balanced draft, now at draft/[divisionId] as in the app. */
export default async function OldTeamDraftPage({ params }: Props) {
  const { tournamentId, divisionId } = await params;
  redirect(`/tournaments/${encodeURIComponent(tournamentId)}/draft/${encodeURIComponent(divisionId)}`);
}
