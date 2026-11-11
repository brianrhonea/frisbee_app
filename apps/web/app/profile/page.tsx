import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = { title: "Your profile", robots: { index: false } };

export default function Profile() {
  return <MembersOnly what="Editing your profile" />;
}
