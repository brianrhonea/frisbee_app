import type { Metadata } from "next";
import { OpenInApp } from "@/components/OpenInApp";

export const metadata: Metadata = {
  title: { absolute: "You're invited to join a team on Stall 10" },
  description: "Open it in the Stall 10 app.",
  robots: { index: false },
};

type Props = { params: Promise<{ code: string }> };

export default async function Page({ params }: Props) {
  return <OpenInApp kind="join" id={(await params).code} />;
}
