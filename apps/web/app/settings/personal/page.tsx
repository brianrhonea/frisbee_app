import type { Metadata } from "next";
import { PersonalSettings } from "@/components/settings/PersonalSettings";

export const metadata: Metadata = { title: "Personal details" };

export default function PersonalPage() {
  return <PersonalSettings />;
}
