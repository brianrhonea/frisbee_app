import type { Metadata } from "next";
import { FollowingSettings } from "@/components/settings/FollowingSettings";

export const metadata: Metadata = { title: "People you follow" };

export default function FollowingPage() {
  return <FollowingSettings />;
}
