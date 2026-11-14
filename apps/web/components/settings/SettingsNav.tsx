"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

const sections = [
  ["/settings/profile", "Profile"],
  ["/settings/personal", "Personal details"],
  ["/settings/privacy", "Privacy"],
  ["/settings/calendar", "Calendars"],
  ["/settings/following", "People you follow"],
  ["/settings/requests", "Follow requests"],
  ["/settings/account", "Account"],
  ["/learn", "Learn to play"],
] as const;

export function SettingsNav() {
  const path = usePathname();
  return (
    <nav className="settings-nav" aria-label="Settings">
      {sections.map(([href, label]) => (
        <Link key={href} href={href} className={path === href ? "active" : ""} aria-current={path === href ? "page" : undefined}>
          {label}
        </Link>
      ))}
    </nav>
  );
}
