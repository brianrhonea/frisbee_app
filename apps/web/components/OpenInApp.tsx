import Link from "next/link";
import { appScheme } from "@/lib/site";
import { StoreBadges } from "./StoreBadges";

export type LinkKind = "join" | "g" | "p";

const valid = /^[A-Za-z0-9_-]{1,200}$/;

/**
 * The fallback for invite and share links (/join/<code>, /g/<id>, /p/<id>),
 * ported from firebase/hosting/join.html. With the app installed, iOS and
 * Android open these links in the app (public/.well-known) instead.
 */
export function OpenInApp({ kind, id }: { kind: LinkKind; id: string }) {
  if (!valid.test(id)) {
    return (
      <section className="center-card">
        <img className="center-logo" src="/logo.png" alt="Stall 10" width={96} height={96} />
        <h1>This link doesn&apos;t look right</h1>
        <p className="lead">Ask whoever sent it for a new one.</p>
      </section>
    );
  }
  const title =
    kind === "p"
      ? "See this post on Stall 10"
      : kind === "g"
        ? "You're invited to a group on Stall 10"
        : "You're invited to join a team on Stall 10";
  return (
    <section className="center-card">
      <img className="center-logo" src="/logo.png" alt="Stall 10" width={96} height={96} />
      <h1>{title}</h1>
      <p className="lead">Open the {kind === "p" ? "post" : "invite"} in the Stall 10 app.</p>
      <a className="btn btn-primary" href={`${appScheme}://open/${kind}/${encodeURIComponent(id)}`}>
        Open in Stall 10
      </a>
      {kind === "join" && (
        <p className="muted">Invite links expire. If this one has, ask whoever sent it for a new one.</p>
      )}
      {kind === "p" && (
        <p>
          <Link href={`/posts/${encodeURIComponent(id)}`}>See the post on the web</Link>
        </p>
      )}
      <p className="muted">No app yet?</p>
      <StoreBadges center />
      <p className="web-cta">
        Or <Link href="/community">see what&apos;s happening on the web</Link>.
      </p>
    </section>
  );
}
