"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { type ReactNode, useEffect } from "react";
import { requestHomeRefresh } from "@/lib/homeRefresh";
import { useAuth } from "./AuthProvider";
import { HeaderAuth } from "./HeaderAuth";
import { NavIcon, type NavIconName } from "./NavIcons";
import { useUnreadCount } from "./Notifications";
import { UpcomingAside } from "./UpcomingAside";

type Tab = { href: string; label: string; icon: NavIconName; also?: string[] };

/** The five tabs, as in the app (docs/product-spec.md §3). */
const tabs: Tab[] = [
  // The community feed and posts are Home's until Home gets its feed tabs.
  { href: "/", label: "Home", icon: "home", also: ["/community", "/posts"] },
  { href: "/explore", label: "Explore", icon: "explore", also: ["/players", "/rankings"] },
  { href: "/events", label: "Events", icon: "events", also: ["/schedule"] },
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

/** Typing in a field, where single-key shortcuts mustn't fire. */
function typing(target: EventTarget | null) {
  const el = target as HTMLElement | null;
  return !!el && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName));
}

/**
 * Site-wide keys: `n` writes a post (Home's composer), `/` searches
 * (Explore), `g` then a tab's first letter goes there.
 */
function useShortcuts(signedIn: boolean) {
  const router = useRouter();
  useEffect(() => {
    let pendingG = 0;
    const go: Record<string, string> = { h: "/", e: "/explore", v: "/events", t: "/teams", m: "/messages", n: "/notifications" };
    function onKey(e: KeyboardEvent) {
      if (e.ctrlKey || e.metaKey || e.altKey || typing(e.target)) return;
      if (pendingG && Date.now() - pendingG < 1200 && go[e.key]) {
        pendingG = 0;
        e.preventDefault();
        router.push(go[e.key]!);
        return;
      }
      pendingG = e.key === "g" ? Date.now() : 0;
      if (e.key === "/") {
        e.preventDefault();
        const search = document.querySelector<HTMLInputElement>("input[type=search]");
        if (search) search.focus();
        else router.push("/explore");
      } else if (e.key === "n" && signedIn) {
        const composer = document.querySelector<HTMLTextAreaElement>(".composer textarea");
        e.preventDefault();
        if (composer) composer.focus();
        else router.push("/");
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router, signedIn]);
}

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
  // Home and team hubs have their own "Coming up" column, for visitors and members alike.
  const aside = path !== "/" && !/^\/teams\/[^/]+/.test(path) && !fullWidth.some((p) => under(path, p));
  const unread = useUnreadCount();
  useShortcuts(!!user);
  const badge = unread > 0 ? <span className="count-badge">{unread > 99 ? "99+" : unread}</span> : null;

  const tabLinks = (className: string) =>
    tabs.map((t) => {
      const active = isActive(path, t);
      return (
        <Link
          key={t.href}
          href={t.href}
          className={active ? `${className} active` : className}
          aria-current={active ? "page" : undefined}
          onClick={() => {
            if (t.href === "/" && path === "/") requestHomeRefresh();
          }}
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
          {user && (
            <Link
              href="/notifications"
              className={path === "/notifications" ? "nav-item active" : "nav-item"}
              aria-current={path === "/notifications" ? "page" : undefined}
            >
              <span className="icon-wrap">
                <NavIcon name="bell" />
                {badge}
              </span>
              <span>Notifications</span>
            </Link>
          )}
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
          {user && (
            <Link
              href="/settings"
              className={under(path, "/settings") ? "nav-item active" : "nav-item"}
              aria-current={under(path, "/settings") ? "page" : undefined}
            >
              <NavIcon name="settings" />
              <span>Settings</span>
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
            {user && (
              <Link href="/notifications" className="icon-btn icon-wrap" aria-label={`Notifications${unread ? ` (${unread} new)` : ""}`}>
                <NavIcon name="bell" />
                {badge}
              </Link>
            )}
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
