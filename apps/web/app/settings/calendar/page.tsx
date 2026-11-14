import type { Metadata } from "next";
import { CalendarSharing } from "@/components/settings/CalendarSharing";

export const metadata: Metadata = { title: "Calendar sharing" };

export default function CalendarSettingsPage() {
  return <CalendarSharing />;
}
