import type { Metadata, Viewport } from "next";
import { Barlow_Condensed, Inter } from "next/font/google";
import Script from "next/script";
import type { ReactNode } from "react";
import { AppFrame } from "@/components/AppFrame";
import { AuthProvider } from "@/components/AuthProvider";
import { ConfirmProvider } from "@/components/ui/ConfirmDialog";
import { ErrorReporter } from "@/components/ErrorReporter";
import { PersonalGate } from "@/components/PersonalGate";
import { SiteFooter } from "@/components/SiteFooter";
import { VoiceProvider } from "@/components/voice/VoiceProvider";
import { themeScript } from "@/lib/theme";
import "./site.css";
import "./app.css";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" });
// Scores, big numbers, date badges and the wordmark.
const barlow = Barlow_Condensed({
  subsets: ["latin"],
  weight: ["700", "800"],
  style: ["normal", "italic"],
  variable: "--font-barlow",
  display: "swap",
});

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: { default: "Stall 10", template: "%s — Stall 10" },
  description: "Ultimate frisbee teams, leagues and tournaments. Find players, teams and pickup communities near you.",
  icons: { icon: "/favicon.png" },
  openGraph: { siteName: "Stall 10", images: ["/logo.png"] },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#09090B" },
    { media: "(prefers-color-scheme: light)", color: "#F4F4F5" },
  ],
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    // The theme script sets data-theme before React loads; that's expected.
    <html lang="en" className={`${inter.variable} ${barlow.variable}`} suppressHydrationWarning>
      <body>
        {/* Applies a saved light/dark choice before the page paints. */}
        <Script id="theme" strategy="beforeInteractive">
          {themeScript}
        </Script>
        <ErrorReporter />
        <AuthProvider>
          {/* Above the frame, so a voice call stays up from page to page. */}
          <VoiceProvider>
            <ConfirmProvider>
              <AppFrame footer={<SiteFooter />}>
                <PersonalGate>{children}</PersonalGate>
              </AppFrame>
            </ConfirmProvider>
          </VoiceProvider>
        </AuthProvider>
      </body>
    </html>
  );
}
