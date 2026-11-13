import type { Metadata } from "next";
import type { ReactNode } from "react";
import { MembersOnly } from "@/components/MembersOnly";
import { SettingsNav } from "@/components/settings/SettingsNav";

export const metadata: Metadata = { title: { default: "Settings", template: "%s · Settings — Stall 10" } };

/** Settings: the sections on the left, the open one on the right. */
export default function SettingsLayout({ children }: { children: ReactNode }) {
  return (
    <div className="page page-wide">
      <header className="page-head">
        <h1>Settings</h1>
      </header>
      <MembersOnly next="/settings">
        <div className="settings">
          <SettingsNav />
          <section className="settings-main">{children}</section>
        </div>
      </MembersOnly>
    </div>
  );
}
