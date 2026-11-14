import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { AppFrame } from "@/components/AppFrame";
import { AuthProvider } from "@/components/AuthProvider";
import { PersonalGate } from "@/components/PersonalGate";
import { SiteFooter } from "@/components/SiteFooter";
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
    { media: "(prefers-color-scheme: dark)", color: "#0e1310" },
    { media: "(prefers-color-scheme: light)", color: "#f4f4ef" },
  ],
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <AuthProvider>
          <AppFrame footer={<SiteFooter />}>
            <PersonalGate>{children}</PersonalGate>
          </AppFrame>
        </AuthProvider>
      </body>
    </html>
  );
}
