import type { Metadata } from "next";
import { Suspense } from "react";
import { Messages } from "@/components/Messages";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = { title: "Messages" };

/** The Messages tab: direct and group conversations beside the open one. */
export default function MessagesPage() {
  return (
    <div className="page page-wide">
      <header className="page-head">
        <h1>Messages</h1>
      </header>
      <MembersOnly next="/messages" what="Sign up free or log in to message players and groups.">
        <Suspense>
          <Messages />
        </Suspense>
      </MembersOnly>
    </div>
  );
}
