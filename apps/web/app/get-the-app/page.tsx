import type { Metadata } from "next";
import { GetTheApp } from "@/components/GetTheApp";

export const metadata: Metadata = {
  title: "Get the app",
  description: "Stall 10 for iPhone and Android: teams, practices, playbooks and live stats.",
};

export default function Page() {
  return <GetTheApp title="Get the Stall 10 app" />;
}
