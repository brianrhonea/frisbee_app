import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { HostEvent } from "@/components/tournaments/TournamentLists";

export const metadata: Metadata = { title: "Host an event" };

/** Pick what to host and which of your teams or groups hosts it. */
export default function HostEventPage() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Host an event</h1>
      </header>
      <MembersOnly next="/tournaments/host" what="Sign up free or log in to host a tournament or league.">
        <HostEvent />
      </MembersOnly>
    </div>
  );
}
