import type { Metadata } from "next";
import { Suspense } from "react";
import { TeamChat } from "@/components/team/TeamChat";

export const metadata: Metadata = { title: "Chat" };

export default function TeamChatPage() {
  return (
    <Suspense>
      <TeamChat />
    </Suspense>
  );
}
