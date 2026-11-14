import type { Metadata } from "next";
import { TeamSettings } from "@/components/team/TeamSettings";

export const metadata: Metadata = { title: "Settings" };

export default function TeamSettingsPage() {
  return <TeamSettings />;
}
