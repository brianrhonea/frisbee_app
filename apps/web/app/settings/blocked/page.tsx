import type { Metadata } from "next";
import { BlockedSettings } from "@/components/settings/BlockedSettings";

export const metadata: Metadata = { title: "Blocked accounts" };

export default function BlockedPage() {
  return <BlockedSettings />;
}
