import { storeLinks } from "@/lib/site";

const apple =
  "M16.37 12.62c-.03-2.6 2.13-3.86 2.22-3.92-1.21-1.77-3.09-2.01-3.76-2.04-1.6-.16-3.12.94-3.93.94-.81 0-2.06-.92-3.39-.89-1.74.03-3.35 1.01-4.25 2.57-1.81 3.14-.46 7.8 1.3 10.35.86 1.25 1.89 2.65 3.24 2.6 1.3-.05 1.79-.84 3.36-.84 1.57 0 2.01.84 3.39.81 1.4-.02 2.29-1.27 3.14-2.53.99-1.45 1.4-2.86 1.42-2.93-.03-.01-2.72-1.04-2.74-4.12zM13.79 4.98c.72-.87 1.2-2.08 1.07-3.28-1.03.04-2.28.69-3.02 1.55-.66.77-1.24 2-1.09 3.18 1.15.09 2.32-.58 3.04-1.45z";
const play =
  "M3.6 1.8c-.24.25-.38.64-.38 1.14v18.12c0 .5.14.89.38 1.14l.06.06L13.8 12.1v-.2L3.66 1.74l-.06.06zm13.58 13.68-3.38-3.38v-.2l3.38-3.38.08.04 4 2.27c1.14.65 1.14 1.71 0 2.36l-4 2.27-.08.02zm-.08.04L13.8 12 3.6 22.2c.38.4 1 .45 1.7.06l11.8-6.74M17.1 8.48 5.3 1.74c-.7-.4-1.32-.34-1.7.06L13.8 12l3.3-3.52z";

/** App Store and Google Play buttons; "Coming soon" until storeLinks.live. */
export function StoreBadges({ center = false }: { center?: boolean }) {
  const live = storeLinks.live;
  return (
    <div className={center ? "badges center" : "badges"}>
      <a
        className="badge"
        href={live ? storeLinks.appStore : "/about#download"}
        aria-label={live ? "Download on the App Store" : "Download on the App Store (coming soon)"}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d={apple} /></svg>
        <span><small>{live ? "Download on the" : "Coming soon to the"}</small>App Store</span>
      </a>
      <a
        className="badge"
        href={live ? storeLinks.playStore : "/about#download"}
        aria-label={live ? "Get it on Google Play" : "Get it on Google Play (coming soon)"}
      >
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d={play} /></svg>
        <span><small>{live ? "Get it on" : "Coming soon to"}</small>Google Play</span>
      </a>
    </div>
  );
}
