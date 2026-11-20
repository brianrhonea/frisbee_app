import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { EnterTeam } from "@/components/tournaments/EnterTeam";

export const metadata: Metadata = { title: "Enter a team" };

type Props = { params: Promise<{ tournamentId: string }>; searchParams: Promise<{ team?: string | string[] }> };

const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) || undefined;

/** Entering a team (or accepting an invite, or changing captains with ?team=) on a page of its own, from the event page. */
export default async function EnterTeamPage({ params, searchParams }: Props) {
  const { tournamentId } = await params;
  const team = first((await searchParams).team);
  return (
    <div className="page">
      <MembersOnly next={`/tournaments/${encodeURIComponent(tournamentId)}/enter${team ? `?team=${encodeURIComponent(team)}` : ""}`} what="Sign up free or log in to enter a team.">
        <EnterTeam tournamentId={tournamentId} teamId={team} />
      </MembersOnly>
    </div>
  );
}
