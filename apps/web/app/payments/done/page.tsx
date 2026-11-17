import type { Metadata } from "next";
import { Suspense } from "react";
import { PaymentDone } from "@/components/payments/PaymentPages";

export const metadata: Metadata = { title: "Payment received" };

/** Where Stripe Checkout sends payers after paying. */
export default function PaymentDonePage() {
  return (
    <div className="page">
      <header className="page-head">
        <h1>Payment received</h1>
      </header>
      <Suspense>
        <PaymentDone />
      </Suspense>
    </div>
  );
}
