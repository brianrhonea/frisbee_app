import type { Metadata } from "next";
import { FollowRequests } from "@/components/settings/FollowRequests";

export const metadata: Metadata = { title: "Follow requests" };

export default function RequestsPage() {
  return <FollowRequests />;
}
