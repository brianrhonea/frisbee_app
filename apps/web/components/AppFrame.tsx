"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { type FormEvent, type ReactNode, useEffect } from "react";
import { requestHomeRefresh } from "@/lib/homeRefresh";
import { useAuth } from "./AuthProvider";
import { HeaderAuth } from "./HeaderAuth";
import { BrandCard } from "./HomeCards";
import { NavIcon, type NavIconName } from "./NavIcons";
import { useUnreadCount } from "./Notifications";
import { SideTeams } from "./SideTeams";
import { ThemeToggle } from "./ThemeToggle";
import { UpcomingAside } from "./UpcomingAside";

type Tab = { href: string; label: string; icon: NavIconName; also?: string[] };

/** The five tabs, as in the app (docs/product-spec.md §3). */
const tabs: Tab[] = [
  // The community feed and posts are Home's (its Community tab).
  { href: "/", label: "Home", icon: "home", also: ["/community", "/posts"] },
  { href: "/explore", label: "Explore", icon: "explore", also: ["/players", "/rankings"] },
  { href: "/teams", label: "Teams", icon: "teams" },
  { href: "/messages", label: "Messages", icon: "messages" },
  { href: "/events", label: "Events", icon: "events", also: ["/schedule"] },
  { href: "/learn", label: "Learn", icon: "learn" },
];

/** Smaller links at the foot of the sidebar. */
const secondary = [
  { href: "/about", label: "About" },
  { href: "/help", label: "Help" },
  { href: "/privacy", label: "Privacy" },
];

/** Focuses Home's composer, or goes Home to write a post. */
function compose(router: ReturnType<typeof useRouter>) {
  const composer = document.querySelector<HTMLTextAreaElement>(".composer textarea");
  if (composer) {
    composer.scrollIntoView({ block: "center", behavior: "smooth" });
    composer.focus({ preventScroll: true });
  } else router.push("/#compose");
}

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
        e.preventDefault();
        compose(router);
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
 * The page frame: a top bar (brand, search, account) over the tabs in a
 * left sidebar (an icon rail on tablets), the page, and upcoming events on
 * the right on wide screens. Phones get the tabs as a row under the top bar.
 */
export function AppFrame({ children, footer }: { children: ReactNode; footer: ReactNode }) {
  const path = usePathname() ?? "/";
  const router = useRouter();
  const { user } = useAuth();
  // Home and team hubs have their own right column, for visitors and members alike.
  const aside = path !== "/" && !/^\/teams\/[^/]+/.test(path) && !fullWidth.some((p) => under(path, p));
  // Explore has its own search box.
  const search = !under(path, "/explore");
  const unread = useUnreadCount();
  useShortcuts(!!user);
  const badge = unread > 0 ? <span className="count-badge">{unread > 99 ? "99+" : unread}</span> : null;

  function onSearch(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const q = String(new FormData(e.currentTarget).get("q") ?? "").trim();
    router.push(q ? `/explore?q=${encodeURIComponent(q)}` : "/explore");
  }

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
      <header className="top-bar">
        <div className="top-brand">
          <Link className="brand wordmark" href="/" aria-label="Stall 10 home">
            STALL 10
          </Link>
          <span className="top-tagline">The ultimate community</span>
        </div>
        {search ? (
          <form className="top-search" role="search" onSubmit={onSearch}>
            <NavIcon name="search" size={18} />
            <input
              type="search"
              name="q"
              placeholder="Search players, teams and upcoming events"
              aria-label="Search Stall 10"
              enterKeyHint="search"
            />
          </form>
        ) : (
          <span className="top-search-gap" />
        )}
        <div className="header-actions">
          {search && (
            <Link href="/explore" className="icon-btn top-search-icon" aria-label="Search">
              <NavIcon name="search" size={22} />
            </Link>
          )}
          <ThemeToggle />
          {user && (
            <Link href="/notifications" className="icon-btn icon-wrap" aria-label={`Notifications${unread ? ` (${unread} new)` : ""}`}>
              <NavIcon name="bell" size={22} />
              {badge}
            </Link>
          )}
          {user && <span className="top-divider" aria-hidden="true" />}
          <HeaderAuth />
        </div>
      </header>

      <nav aria-label="Tabs" className="tab-bar">
        {tabLinks("tab-item")}
      </nav>

      <aside className="side-nav">
        <nav aria-label="Site" className="side-tabs">
          <h2 className="side-label">Your sideline</h2>
          {tabLinks("nav-item")}
        </nav>
        {user ? (
          <button type="button" className="btn btn-primary side-create" onClick={() => compose(router)}>
            <NavIcon name="plus" size={18} />
            <span>Create a post</span>
          </button>
        ) : (
          <Link className="btn btn-primary side-create" href="/sign-up">
            <NavIcon name="plus" size={18} />
            <span>Join Stall 10</span>
          </Link>
        )}
        <SideTeams />
        <div className="side-foot">
          <BrandCard />
          <nav aria-label="More" className="side-secondary">
            {secondary.map((l) => (
              <Link key={l.href} href={l.href}>
                {l.label}
              </Link>
            ))}
          </nav>
          <small className="side-copy">© {new Date().getFullYear()} Stall 10</small>
        </div>
      </aside>

      <div className="frame-main">
        <main>{children}</main>
        {footer}
      </div>

      {aside && (
        <aside className="frame-aside" aria-label="Upcoming">
          <UpcomingAside />
        </aside>
      )}
    </div>
  );
}

