import type { Metadata } from "next";
import { EmbeddedPayouts } from "@/components/payments/EmbeddedPayouts";

export const metadata: Metadata = { title: "Set up payments", robots: { index: false, follow: false } };

/**
 * Stripe's payments setup for the app, shown in its WebView (PayoutsSetupScreen):
 * the app fetches the setup session from the API and hands its client
 * secret to this page through a JavaScript channel, never in the URL, so
 * no website sign-in is needed. Nothing here works on its own in a browser.
 */
export default function EmbedPayoutsPage() {
  return <EmbeddedPayouts />;
}
