import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { EnterTeam } from "@/components/tournaments/EnterTeam";

export const metadata: Metadata = { title: "Respond or enter a team" };

type Props = { params: Promise<{ tournamentId: string }>; searchParams: Promise<{ team?: string | string[]; step?: string | string[] }> };

const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) || undefined;

/** Entering a team a step at a time (respond to an invite or apply, roster, payment), or finishing an entry with ?team= (and ?step=roster|pay). */
export default async function EnterTeamPage({ params, searchParams }: Props) {
  const { tournamentId } = await params;
  const query = await searchParams;
  const team = first(query.team);
  const step = first(query.step);
  return (
    <div className="page">
      <MembersOnly next={`/tournaments/${encodeURIComponent(tournamentId)}/enter${team ? `?team=${encodeURIComponent(team)}${step ? `&step=${encodeURIComponent(step)}` : ""}` : ""}`} what="Sign up free or log in to enter a team.">
        <EnterTeam tournamentId={tournamentId} teamId={team} step={step} />
      </MembersOnly>
    </div>
  );
}
