import type { Metadata } from "next";
import Link from "next/link";
import { FollowRequests } from "@/components/FollowRequests";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = { title: "Follow requests" };

export default function FollowRequestsPage() {
  return (
    <div className="page">
      <header className="page-head">
        <p className="muted small">
          <Link href="/notifications">← Notifications</Link>
        </p>
        <h1>Follow requests</h1>
      </header>
      <MembersOnly next="/notifications/requests">
        <FollowRequests />
      </MembersOnly>
    </div>
  );
}
