import { readdirSync } from "node:fs";
import { join, relative } from "node:path";

// The website's routes, read from app/**/page.tsx (docs/specifications/navigation-route-map.md section 4),
// so a new page is covered without editing the specs that use this.
const appDir = join(__dirname, "../../app");

function pages(dir: string, out: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) pages(p, out);
    else if (e.name === "page.tsx") out.push("/" + relative(appDir, dir).replace(/\\/g, "/"));
  }
  return out;
}

/** Every page route with `[param]` segments filled from [ids] (unknown names become "x"), sorted. */
export function routesWith(ids: Record<string, string>): string[] {
  return pages(appDir)
    .map((r) => (r === "/." ? "/" : r))
    .map((r) => r.replace(/\[(\w+)\]/g, (_m, k: string) => ids[k] ?? "x"))
    .sort();
}

/** Made-up ids: nothing exists behind them (the pages show "not found" or a sign-in prompt). */
export const syntheticIds: Record<string, string> = { slug: "about", id: "t1", code: "ABC123", uid: "u1", teamId: "t1", tournamentId: "tn1", divisionId: "d1", meetingId: "m1", playId: "p1", videoId: "v1", gameId: "g1", postId: "post1" };

/** Console errors that are not the page's fault: failed loads of unreachable services and Firebase's own noise. */
export const ignorableConsole = /Failed to load resource|ERR_|Firebase|auth\/|Encountered a script tag/i;
