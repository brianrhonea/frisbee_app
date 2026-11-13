"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useAuth } from "./AuthProvider";
import { HeaderAuth } from "./HeaderAuth";
import { NavIcon, type NavIconName } from "./NavIcons";
import { UpcomingAside } from "./UpcomingAside";

type Tab = { href: string; label: string; icon: NavIconName; also?: string[] };

/** The five tabs, as in the app (docs/product-spec.md §3). */
const tabs: Tab[] = [
  // The community feed and posts are Home's until Home gets its feed tabs.
  { href: "/", label: "Home", icon: "home", also: ["/community", "/posts"] },
  { href: "/explore", label: "Explore", icon: "explore", also: ["/players"] },
  { href: "/events", label: "Events", icon: "events" },
  { href: "/teams", label: "Teams", icon: "teams" },
  { href: "/messages", label: "Messages", icon: "messages" },
];

/** Smaller links under the tabs. */
const secondary = [
  { href: "/learn", label: "Learn" },
  { href: "/about", label: "About" },
  { href: "/help", label: "Help" },
];

/** Pages that read best at full width, without the right column. */
const fullWidth = ["/sign-in", "/sign-up", "/about", "/get-the-app", "/join", "/g", "/p"];

const under = (path: string, href: string) => path === href || path.startsWith(`${href}/`);

function isActive(path: string, tab: Tab) {
  if (tab.href === "/" ? path === "/" : under(path, tab.href)) return true;
  return tab.also?.some((p) => under(path, p)) ?? false;
}

/**
 * The page frame: tabs in a left sidebar (icons only on tablets), the page,
 * and upcoming events on the right on wide screens. Phones get a top bar
 * and the tabs along the bottom, like the app.
 */
export function AppFrame({ children, footer }: { children: ReactNode; footer: ReactNode }) {
  const path = usePathname() ?? "/";
  const { user } = useAuth();
  const profile = user ? `/players/${encodeURIComponent(user.uid)}` : null;
  // Home has its own "Coming up" column, for visitors and members alike.
  const aside = path !== "/" && !fullWidth.some((p) => under(path, p));

  const tabLinks = (className: string) =>
    tabs.map((t) => {
      const active = isActive(path, t);
      return (
        <Link
          key={t.href}
          href={t.href}
          className={active ? `${className} active` : className}
          aria-current={active ? "page" : undefined}
        >
          <NavIcon name={t.icon} />
          <span>{t.label}</span>
        </Link>
      );
    });

  return (
    <div className={aside ? "frame with-aside" : "frame"}>
      <aside className="side-nav">
        <Link className="brand" href="/">
          <img src="/logo.png" alt="" width={34} height={34} />
          <span>Stall 10</span>
        </Link>
        <nav aria-label="Site" className="side-tabs">
          {tabLinks("nav-item")}
          {profile && (
            <Link
              href={profile}
              className={path === profile ? "nav-item active" : "nav-item"}
              aria-current={path === profile ? "page" : undefined}
            >
              <NavIcon name="profile" />
              <span>Profile</span>
            </Link>
          )}
        </nav>
        <nav aria-label="More" className="side-secondary">
          {secondary.map((l) => (
            <Link key={l.href} href={l.href}>
              {l.label}
            </Link>
          ))}
        </nav>
        <div className="side-account">
          <HeaderAuth />
        </div>
      </aside>

      <div className="frame-main">
        <header className="top-bar">
          <Link className="brand" href="/">
            <img src="/logo.png" alt="" width={30} height={30} />
            <span>Stall 10</span>
          </Link>
          <div className="header-actions">
            <HeaderAuth />
          </div>
        </header>
        <main>{children}</main>
        {footer}
      </div>

      {aside && (
        <aside className="frame-aside" aria-label="Upcoming">
          <UpcomingAside />
        </aside>
      )}

      <nav aria-label="Tabs" className="tab-bar">
        {tabLinks("tab-item")}
      </nav>
    </div>
  );
}
