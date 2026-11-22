import type { Metadata } from "next";
import { Suspense } from "react";
import { MembersOnly } from "@/components/MembersOnly";
import { PayoutsReturn } from "@/components/payments/PaymentPages";

export const metadata: Metadata = { title: "Payments" };

/** Where Stripe's onboarding sends the host's owner back (and its expired-link retry). */
export default function PayoutsPage() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Payments</h1>
      </header>
      <MembersOnly>
        <Suspense>
          <PayoutsReturn />
        </Suspense>
      </MembersOnly>
    </div>
  );
}
