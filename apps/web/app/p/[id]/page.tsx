import type { Metadata } from "next";
import { OpenInApp } from "@/components/OpenInApp";

export const metadata: Metadata = {
  title: { absolute: "A post on Stall 10" },
  description: "Open it in the Stall 10 app.",
  robots: { index: false },
};

type Props = { params: Promise<{ id: string }> };

export default async function Page({ params }: Props) {
  return <OpenInApp kind="p" id={(await params).id} />;
}
