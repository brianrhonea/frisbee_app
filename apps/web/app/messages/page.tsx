import type { Metadata } from "next";
import { GetTheApp } from "@/components/GetTheApp";

export const metadata: Metadata = { title: "Messages" };

/** The Messages tab: messages are app-only until the website gets them. */
export default function Messages() {
  return (
    <GetTheApp title="Messages are in the app">
      <p className="lead">Direct messages and team chat are in the Stall 10 app for now. They&apos;re coming to the web.</p>
    </GetTheApp>
  );
}
