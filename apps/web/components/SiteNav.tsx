"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "./AuthProvider";

type NavLink = { href: string; label: string };

const community = { href: "/community", label: "Community" };
const explore = { href: "/explore", label: "Explore" };
const events = { href: "/events", label: "Events" };
const learn = { href: "/learn", label: "Learn" };

/** Visitors: what Stall 10 is. Members: their home first, as in the app. */
const visitorLinks: NavLink[] = [community, explore, events, learn, { href: "/about", label: "About" }];
const memberLinks: NavLink[] = [{ href: "/", label: "Home" }, community, explore, events, learn];

const isActive = (path: string, href: string) => (href === "/" ? path === "/" : path === href || path.startsWith(`${href}/`));

/** The site's main links, for whoever is signed in. */
export function SiteNav() {
  const { user } = useAuth();
  const path = usePathname() ?? "/";
  const links = user ? memberLinks : visitorLinks;
  return (
    <nav aria-label="Site">
      {links.map((l) => {
        const active = isActive(path, l.href);
        return (
          <Link key={l.href} href={l.href} className={active ? "active" : undefined} aria-current={active ? "page" : undefined}>
            {l.label}
          </Link>
        );
      })}
    </nav>
  );
}
