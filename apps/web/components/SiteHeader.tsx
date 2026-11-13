import Link from "next/link";
import { HeaderAuth } from "./HeaderAuth";
import { SiteNav } from "./SiteNav";

/** The site header (same markup as firebase/hosting's static pages). */
export function SiteHeader() {
  return (
    <header className="site-header">
      <div className="wrap">
        <Link className="brand" href="/">
          <img src="/logo.png" alt="" width={34} height={34} />
          <span>Stall 10</span>
        </Link>
        <SiteNav />
        <div className="header-actions">
          <HeaderAuth />
        </div>
      </div>
    </header>
  );
}
