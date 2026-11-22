import { divisionLabel } from "@stall10/shared";
import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { BracketForEveryone, MemberBracket } from "@/components/tournaments/TournamentBracket";
import { loadTournament } from "@/lib/tournamentPage";

type Search = { division?: string | string[] };
type Props = { params: Promise<{ tournamentId: string }>; searchParams: Promise<Search> };

const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) || undefined;

export async function generateMetadata({ params, searchParams }: Props): Promise<Metadata> {
  const { tournamentId } = await params;
  const { division } = await searchParams;
  const page = await loadTournament(tournamentId, first(division));
  if (!page) return { title: "Bracket" };
  const d = page.divisions.find((x) => x.id === page.divisionId);
  return {
    title: `Bracket · ${page.tournament.name || "Tournament"}`,
    description: `${d ? `${divisionLabel(d)} bracket` : "The bracket"} for ${page.tournament.name}, hosted by ${page.tournament.hostName}, on Stall 10.`.slice(0, 200),
  };
}

/**
 * A division's bracket on its own page (?division=; else the first
 * division's). Published events are server-rendered from the public page
 * for visitors; members get the live bracket. Drafts and private groups'
 * events stay members-only, as the event page does.
 */
export default async function TournamentBracketPage({ params, searchParams }: Props) {
  const { tournamentId } = await params;
  const division = first((await searchParams).division);
  const page = await loadTournament(tournamentId, division);
  const q = division ? `?division=${encodeURIComponent(division)}` : "";
  if (!page) {
    return (
      <div className="page">
        <MembersOnly next={`/tournaments/${encodeURIComponent(tournamentId)}/bracket${q}`} what="Sign up free or log in to see this bracket.">
          <MemberBracket tournamentId={tournamentId} divisionId={division} />
        </MembersOnly>
      </div>
    );
  }
  return (
    <div className="page">
      <BracketForEveryone page={page} divisionId={division} />
    </div>
  );
}
