import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="wrap">
        <span>
          © {new Date().getFullYear()} Stall 10 <span className="version">· web v{process.env.NEXT_PUBLIC_APP_VERSION}</span>
        </span>
        <nav aria-label="Footer">
          <Link href="/about">About</Link>
          <Link href="/help">Help</Link>
          <Link href="/terms">Terms of Service</Link>
          <Link href="/privacy">Privacy Policy</Link>
          <Link href="/cookies">Cookie Policy</Link>
          <Link href="/delete-account">Delete your account</Link>
        </nav>
      </div>
    </footer>
  );
}
