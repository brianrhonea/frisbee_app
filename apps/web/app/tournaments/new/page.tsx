import type { HostedType } from "@stall10/shared";
import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { TournamentForm } from "@/components/tournaments/TournamentForm";

export const metadata: Metadata = { title: "Host an event" };

type Props = { searchParams: Promise<{ host?: string | string[]; type?: string | string[] }> };
const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v);
const types: HostedType[] = ["tournament", "hat", "league"];

/** A new hosted tournament, hat tournament or league for ?host=. */
export default async function NewTournamentPage({ searchParams }: Props) {
  const q = await searchParams;
  const host = one(q.host);
  const raw = one(q.type);
  const type = types.find((x) => x === raw) ?? "tournament";
  const next = `/tournaments/new?host=${encodeURIComponent(host ?? "")}&type=${type}`;
  return (
    <div className="page">
      <header className="page-head">
        <h1>{type === "league" ? "Host a league" : type === "hat" ? "Host a hat tournament" : "Host a tournament"}</h1>
      </header>
      <MembersOnly next={next}>
        {host ? <TournamentForm key={`${host}:${type}`} hostId={host} type={type} /> : <p className="empty">Pick who hosts it from Host an event.</p>}
      </MembersOnly>
    </div>
  );
}
