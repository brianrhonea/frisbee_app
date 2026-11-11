import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";

export const metadata: Metadata = { title: "Home", robots: { index: false } };

export default function Home() {
  return <MembersOnly what="Your home feed" />;
}
