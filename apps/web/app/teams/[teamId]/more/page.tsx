import type { Metadata } from "next";
import { Suspense } from "react";
import { TeamMore } from "@/components/team/TeamMore";

export const metadata: Metadata = { title: "More" };

export default function TeamMorePage() {
  return (
    <Suspense>
      <TeamMore />
    </Suspense>
  );
}
