"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useLiveDoc } from "@/lib/live";
import { useAuth } from "../AuthProvider";
import { Avatar } from "../Avatar";
import "../member.css";

/** The sections in three groups (spacing between them, a chevron on each row). */
const groups: ReadonlyArray<ReadonlyArray<readonly [string, string]>> = [
  [
    ["/settings/profile", "Profile"],
    ["/settings/personal", "Personal details"],
    ["/settings/privacy", "Privacy"],
    ["/settings/notifications", "Notifications"],
  ],
  [
    ["/settings/calendar", "Calendars"],
    ["/settings/following", "People you follow"],
    ["/settings/blocked", "Blocked accounts"],
  ],
  [
    ["/settings/account", "Account"],
    ["/settings/help", "Help"],
    ["/learn", "Learn to play"],
  ],
];

export function SettingsNav() {
  const path = usePathname();
  const { user } = useAuth();
  // Stall 10 staff (staff/{uid}, set by firebase/scripts/set-staff.mjs) get
  // a way into the report queue.
  const staff = useLiveDoc(user ? `staff/${user.uid}` : null).data != null;
  const shown = staff ? [...groups, [["/staff", "Stall 10 staff: reports"] as const]] : groups;
  return (
    <nav className="settings-nav" aria-label="Settings">
      {user && (
        <Link className="settings-me" href={`/players/${encodeURIComponent(user.uid)}`}>
          <Avatar name={user.displayName || "You"} url={user.photoURL || undefined} size={44} />
          <span>
            <b>{user.displayName || "Your profile"}</b>
            <small>View your profile</small>
          </span>
        </Link>
      )}
      {shown.map((group, i) => (
        <div key={i} className="settings-group">
          {group.map(([href, label]) => (
            <Link key={href} href={href} className={path === href ? "active" : ""} aria-current={path === href ? "page" : undefined}>
              <span>{label}</span>
              <span className="settings-chevron" aria-hidden="true">
                ›
              </span>
            </Link>
          ))}
        </div>
      ))}
    </nav>
  );
}
