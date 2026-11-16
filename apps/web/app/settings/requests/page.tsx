import { redirect } from "next/navigation";

/** Follow requests moved to the top of Notifications. */
export default function RequestsPage() {
  redirect("/notifications/requests");
}
