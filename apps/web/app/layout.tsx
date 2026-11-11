import type { ReactNode } from "react";

export const metadata = {
  title: "Stall 10",
  description: "Ultimate frisbee teams, leagues and tournaments.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", margin: 0 }}>{children}</body>
    </html>
  );
}
