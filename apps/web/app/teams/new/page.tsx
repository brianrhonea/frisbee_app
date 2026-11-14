import type { Metadata } from "next";
import { Suspense } from "react";
import { CreateTeam } from "@/components/CreateTeam";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = { title: "Create" };

export default function NewTeamPage() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Create</h1>
      </header>
      <MembersOnly next="/teams/new" what="Sign up free or log in to create a team or group.">
        <Suspense>
          <CreateTeam />
        </Suspense>
      </MembersOnly>
    </div>
  );
}
