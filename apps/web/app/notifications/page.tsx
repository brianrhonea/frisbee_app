import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { Notifications } from "@/components/Notifications";

export const metadata: Metadata = { title: "Notifications" };

export default function NotificationsPage() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Notifications</h1>
      </header>
      <MembersOnly next="/notifications">
        <Notifications />
      </MembersOnly>
    </div>
  );
}
