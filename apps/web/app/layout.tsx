import type { Metadata, Viewport } from "next";
import Script from "next/script";
import type { ReactNode } from "react";
import { AppFrame } from "@/components/AppFrame";
import { AuthProvider } from "@/components/AuthProvider";
import { PersonalGate } from "@/components/PersonalGate";
import { SiteFooter } from "@/components/SiteFooter";
import { themeScript } from "@/lib/theme";
import "./site.css";
import "./app.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || "http://localhost:3000";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: { default: "Stall 10", template: "%s — Stall 10" },
  description: "Ultimate frisbee teams, leagues and tournaments. Find players, teams and pickup groups near you.",
  icons: { icon: "/favicon.png" },
  openGraph: { siteName: "Stall 10", images: ["/logo.png"] },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#121521" },
    { media: "(prefers-color-scheme: light)", color: "#f3f5fb" },
  ],
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    // The theme script sets data-theme before React loads; that's expected.
    <html lang="en" suppressHydrationWarning>
      <body>
        {/* Applies a saved light/dark choice before the page paints. */}
        <Script id="theme" strategy="beforeInteractive">
          {themeScript}
        </Script>
        <AuthProvider>
          <AppFrame footer={<SiteFooter />}>
            <PersonalGate>{children}</PersonalGate>
          </AppFrame>
        </AuthProvider>
      </body>
    </html>
  );
}
