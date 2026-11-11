import Link from "next/link";
import { HeaderAuth } from "./HeaderAuth";

/** The site header (same markup as firebase/hosting's static pages). */
export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="wrap">
        <Link className="brand" href="/community">
          <img src="/logo.png" alt="" width={34} height={34} />
          <span>Stall 10</span>
        </Link>
        <nav aria-label="Site">
          <Link href="/community">Community</Link>
          <Link href="/explore">Explore</Link>
          <Link href="/events">Events</Link>
          <Link href="/about">About</Link>
        </nav>
        <div className="header-actions">
          <HeaderAuth />
        </div>
      </div>
    </header>
  );
}
