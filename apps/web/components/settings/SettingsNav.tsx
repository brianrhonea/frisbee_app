"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import "../member.css";

const sections = [
  ["/settings/profile", "Profile"],
  ["/settings/personal", "Personal details"],
  ["/settings/privacy", "Privacy"],
  ["/settings/notifications", "Notifications"],
  ["/settings/calendar", "Calendars"],
  ["/settings/following", "People you follow"],
  ["/settings/blocked", "Blocked accounts"],
  ["/settings/account", "Account"],
  ["/settings/help", "Help"],
  ["/rules", "Rules of ultimate"],
  ["/learn", "Learn to play"],
] as const;

export function SettingsNav() {
  const path = usePathname();
  const { user } = useAuth();
  // Stall 10 staff (staff/{uid}, set by firebase/scripts/set-staff.mjs) get
  // a way into the report queue.
  const staff = useLiveDoc(user ? `staff/${user.uid}` : null).data != null;
  const links: ReadonlyArray<readonly [string, string]> = staff ? [...sections, ["/staff", "Stall 10 staff: reports"]] : sections;
  return (
    <nav className="settings-nav" aria-label="Settings">
      {links.map(([href, label]) => (
        <Link key={href} href={href} className={path === href ? "active" : ""} aria-current={path === href ? "page" : undefined}>
          {label}
        </Link>
      ))}
    </nav>
  );
}
