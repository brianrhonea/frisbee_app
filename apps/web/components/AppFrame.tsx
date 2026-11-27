"use client";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { type FormEvent, type ReactNode, Suspense, useEffect } from "react";
import { newPostBox, requestHomeRefresh } from "@/lib/homeRefresh";
import { useAuth } from "./AuthProvider";
import { MeetingAlerts } from "./team/meetings/MeetingAlerts";
import { HeaderAuth } from "./HeaderAuth";
import { BrandCard } from "./HomeCards";
import { NavIcon, type NavIconName } from "./NavIcons";
import { OfflineBanner } from "./OfflineBanner";
import { useUnreadChats } from "./useUnreadChats";
import { useUnreadCount } from "./Notifications";
import { SideTeams } from "./SideTeams";
import { ThemeToggle } from "./ThemeToggle";
import { UpcomingAside } from "./UpcomingAside";
import { VoiceBar } from "./voice/VoiceBar";
import { isTyping } from "@/lib/text";

type Tab = {
  href: string;
  label: string;
  icon: NavIconName;
  also?: string[];
  /** Discover's `?only=` filter this tab opens (visitors' Pickup and Communities). */
  only?: string;
};

/**
 * Members: the five tabs, in the approved order Home, Discover, Teams,
 * Schedule, Chats (UI-Q11, the app's bottom bar too). Discover is /explore,
 * which also holds what Events and Find tournaments did, and now Learn
 * (UI-Q5): /learn keeps its route and opens under Discover.
 */
const memberTabs: Tab[] = [
  // The community feed and posts are Home's (its Everyone tab).
  { href: "/", label: "Home", icon: "home", also: ["/community", "/posts"] },
  { href: "/explore", label: "Discover", icon: "explore", also: ["/players", "/rankings", "/tournaments", "/events", "/discover", "/learn"] },
  { href: "/teams", label: "Teams", icon: "teams" },
  { href: "/schedule", label: "Schedule", icon: "events" },
  { href: "/messages", label: "Chats", icon: "messages" },
];

/** Under Discover in the sidebar, where the labels show (members; visitors keep Learn as a tab). */
const learnEntry: Tab = { href: "/learn", label: "Learn to play", icon: "learn" };

/**
 * Visitors (and everyone while the browser restores a session): what they
 * can use without an account. No Teams or Chats; the brand goes Home.
 */
const visitorTabs: Tab[] = [
  { href: "/explore", label: "Discover", icon: "explore", also: ["/players", "/rankings", "/events", "/discover"] },
  { href: "/tournaments", label: "Tournaments", icon: "events" },
  { href: "/explore?only=pickup", label: "Pickup", icon: "home", only: "pickup" },
  { href: "/explore?only=groups", label: "Communities", icon: "teams", only: "groups" },
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
  const composer = document.querySelector<HTMLTextAreaElement>(newPostBox);
  if (composer) {
    composer.scrollIntoView({ block: "center", behavior: "smooth" });
    composer.focus({ preventScroll: true });
  } else router.push("/#compose");
}

/** Pages with a composer of their own at the foot, where a floating Post button would cover it. */
const ownComposer = ["/messages", "/posts"];
const isChat = (path: string) => /^\/teams\/[^/]+\/(chat|meetings)/.test(path);

/** Pages that read best at full width, without the right column. */
const fullWidth = ["/sign-in", "/sign-up", "/about", "/get-the-app", "/join", "/g", "/p", "/messages"];

/**
 * Site-wide keys: `n` writes a post (Home's composer), `/` searches
 * (Discover), `g` then a tab's first letter goes there (the old `e`, `v`
 * and `m` too).
 */
function useShortcuts(signedIn: boolean) {
  const router = useRouter();
  useEffect(() => {
    let pendingG = 0;
    const go: Record<string, string> = {
      h: "/",
      d: "/explore",
      e: "/explore",
      v: "/explore",
      s: "/schedule",
      t: "/teams",
      i: "/messages",
      m: "/messages",
      l: "/learn",
      n: "/notifications",
    };
    function onKey(e: KeyboardEvent) {
      if (e.ctrlKey || e.metaKey || e.altKey || isTyping(e.target)) return;
      if (pendingG && Date.now() - pendingG < 1200 && go[e.key]) {
        pendingG = 0;
        e.preventDefault();
        router.push(go[e.key]!);
        return;
      }
      pendingG = e.key === "g" ? Date.now() : 0;
      if (e.key === "/") {
        e.preventDefault();
        // The site search: the top bar's, or Discover's own (never a list's filter box).
        const search = document.querySelector<HTMLInputElement>(".top-search input, input#q");
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

/** Whether [tab] is the open one; [only] is Discover's `?only=` filter, which visitors' Pickup and Communities open. */
function isActive(path: string, tab: Tab, only: string | null, tabs: Tab[]) {
  const base = tab.href.split("?")[0]!;
  if (tab.only) return under(path, base) && tab.only === only;
  // Discover itself isn't the open tab while one of those filters is.
  const filtered = tabs.some((t) => t.only && t.only === only);
  if (base === "/" ? path === "/" : under(path, base)) return !(base === "/explore" && filtered);
  return tab.also?.some((p) => under(path, p)) ?? false;
}

type TabLinksProps = { tabs: Tab[]; className: string; path: string; only: string | null; chats?: number; withLearn?: boolean };

/** The tabs as links. Teams always opens the list of your teams, even with only one. */
function TabLinks({ tabs, className, path, only, chats = 0, withLearn = false }: TabLinksProps) {
  return tabs.map((t) => {
    const active = isActive(path, t, only, tabs);
    const link = (
      <Link
        key={t.href}
        href={t.href}
        className={active ? `${className} active` : className}
        aria-current={active ? "page" : undefined}
        onClick={() => {
          if (t.href === "/" && path === "/") requestHomeRefresh();
        }}
      >
        {t.href === "/messages" && chats > 0 ? (
          <span className="icon-wrap" aria-label={`${chats} unread`}>
            <NavIcon name={t.icon} />
            <span className="count-badge">{chats > 99 ? "99+" : chats}</span>
          </span>
        ) : (
          <NavIcon name={t.icon} />
        )}
        <span>{t.label}</span>
      </Link>
    );
    if (!(withLearn && t.href === "/explore")) return link;
    // Learn, indented under Discover; the icon rail hides it (Discover's page links to it).
    const learn = under(path, learnEntry.href);
    return [
      link,
      <Link key={learnEntry.href} href={learnEntry.href} className={`${className}-sub${learn ? " active" : ""}`} aria-current={learn ? "page" : undefined}>
        <span>{learnEntry.label}</span>
      </Link>,
    ];
  });
}

/** [TabLinks] knowing Discover's filter (reading the address needs a Suspense boundary). */
function TabLinksWithFilter(props: Omit<TabLinksProps, "only">) {
  const only = useSearchParams()?.get("only") ?? null;
  return <TabLinks {...props} only={only} />;
}

/**
 * The page frame: a top bar (brand, search, account picture) over the tabs
 * in a left sidebar (900 px and up; an icon rail from 600 to 899), the page
 * (capped at 1600 px), and upcoming events on the right from 1200 px.
 * Phones (under 600) get the tabs as a bar fixed to the bottom.
 */
export function AppFrame({ children, footer }: { children: ReactNode; footer: ReactNode }) {
  const path = usePathname() ?? "/";
  const router = useRouter();
  const { user } = useAuth();
  // Home and team hubs have their own right column, for visitors and members alike.
  const aside = path !== "/" && !/^\/teams\/[^/]+/.test(path) && !fullWidth.some((p) => under(path, p));
  // Discover has its own search box.
  const search = !under(path, "/explore");
  const tabs = user ? memberTabs : visitorTabs;
  const unread = useUnreadCount();
  // The Chats tab's bubble: unread, unmuted conversations and team chats.
  const chats = useUnreadChats(user?.uid);
  useShortcuts(!!user);
  // Phones' floating Post button, on pages without a composer of their own at the foot.
  const fab = !!user && !ownComposer.some((p) => under(path, p)) && !isChat(path);
  const badge = unread > 0 ? <span className="count-badge">{unread > 99 ? "99+" : unread}</span> : null;

  function onSearch(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const q = String(new FormData(e.currentTarget).get("q") ?? "").trim();
    // Everyone searches on Discover; only members also find players there.
    router.push(q ? `/explore?q=${encodeURIComponent(q)}` : "/explore");
  }

  const tabLinks = (className: string, withLearn = false) => {
    const props = { tabs, className, path, chats, withLearn: withLearn && !!user };
    return (
      <Suspense fallback={<TabLinks {...props} only={null} />}>
        <TabLinksWithFilter {...props} />
      </Suspense>
    );
  };

  // Pages the app shows in a WebView (/embed/*): just the page, no bars or tabs.
  if (under(path, "/embed")) return <main className="embed-frame">{children}</main>;

  return (
    <div className={`frame${aside ? " with-aside" : ""}${fab ? " has-fab" : ""}`}>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
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
              placeholder={user ? "Search players, teams and events" : "Search tournaments, teams and communities"}
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

      <div className="side-nav">
        <nav aria-label="Site" className="side-tabs">
          <p className="side-label">Your sideline</p>
          {tabLinks("nav-item", true)}
        </nav>
        {user ? (
          <button type="button" className="btn btn-primary side-create" aria-label="Create a post" onClick={() => compose(router)}>
            <NavIcon name="plus" size={18} />
            <span>Create a post</span>
          </button>
        ) : (
          <Link className="btn btn-primary side-create" href="/sign-up" aria-label="Join Stall 10">
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
      </div>

      {/* Phones, where the side nav (and its Create a post) is hidden. */}
      {fab && (
        <button type="button" className="fab-post" onClick={() => compose(router)}>
          <NavIcon name="plus" size={20} />
          <span>Post</span>
        </button>
      )}

      <div className="frame-main">
        {user && <OfflineBanner />}
        <main id="main" tabIndex={-1}>
          {children}
        </main>
        {user && <VoiceBar />}
        {user && <MeetingAlerts />}
        {footer}
      </div>

      {aside && (
        <aside className="frame-aside" aria-label="Upcoming">
          <UpcomingAside />
        </aside>
      )}

      {/* Phones: the tabs as a bar fixed to the foot of the screen (last in the page, so Tab reaches it after the content). */}
      <nav aria-label="Tabs" className="tab-bar">
        {tabLinks("tab-item")}
      </nav>
    </div>
  );
}

