import type { Metadata } from "next";
import { CalendarSettings } from "@/components/settings/CalendarSettings";

export const metadata: Metadata = { title: "Calendars" };

export default function CalendarSettingsPage() {
  return <CalendarSettings />;
}
