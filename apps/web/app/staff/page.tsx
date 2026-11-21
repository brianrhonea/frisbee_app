import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { StaffQueue } from "@/components/StaffQueue";

export const metadata: Metadata = { title: "Reports", robots: { index: false } };

/** Stall 10 staff's review queue (the `staff` claim; firebase/scripts/set-staff.mjs). */
export default function StaffPage() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Reports</h1>
      </header>
      <MembersOnly next="/staff">
        <StaffQueue />
      </MembersOnly>
    </div>
  );
}
