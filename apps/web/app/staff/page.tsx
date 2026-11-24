import type { Metadata } from "next";
import { MembersOnly } from "@/components/MembersOnly";
import { StaffQueue } from "@/components/StaffQueue";
import { StaffPayments } from "@/components/payments/StaffPayments";

export const metadata: Metadata = { title: "Staff", robots: { index: false } };

/** Stall 10 staff's review queue and payments (the `staff` claim; firebase/scripts/set-staff.mjs). */
export default function StaffPage() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Reports</h1>
      </header>
      <MembersOnly next="/staff">
        <StaffQueue />
        <h2 className="section-title">Payments</h2>
        <StaffPayments />
      </MembersOnly>
    </div>
  );
}
