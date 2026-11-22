import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { CreateTeam } from "@/components/CreateTeam";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = { title: "Create" };

export default function NewTeamPage() {
  return (
    <div className="page create-page">
      <p className="back-link">
        <Link href="/teams">‹ Teams</Link>
      </p>
      <header className="page-head">
        <h1>Create</h1>
        <p>Takes a minute. Start simple, turn more on later.</p>
      </header>
      <MembersOnly next="/teams/new" what="Sign up free or log in to create a team or community.">
        <Suspense>
          <CreateTeam />
        </Suspense>
      </MembersOnly>
    </div>
  );
}
