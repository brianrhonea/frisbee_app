import type { Metadata } from "next";
import { Suspense } from "react";
import { TeamSchedule } from "@/components/team/TeamSchedule";
import { loadTeam } from "@/lib/teamPage";

type Props = { params: Promise<{ teamId: string }> };

export const metadata: Metadata = { title: "Schedule" };

export default async function TeamSchedulePage({ params }: Props) {
  const { events } = await loadTeam((await params).teamId);
  return (
    <Suspense>
      <TeamSchedule publicEvents={events} />
    </Suspense>
  );
}
