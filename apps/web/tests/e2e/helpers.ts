import AxeBuilder from "@axe-core/playwright";
import { expect, type Page } from "@playwright/test";

export type Theme = "light" | "dark";

/**
 * Collects uncaught page errors and console errors while a test runs.
 * Requests refused because a local service isn't running (the API on 8787
 * when only the website is started) go to [offline] instead: they're
 * reported, not failed on. Start the API (`pnpm dev:api`) to exercise them.
 */
export function watchErrors(page: Page) {
  const errors: string[] = [];
  const offline: string[] = [];
  page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
  page.on("console", (m) => {
    if (m.type() !== "error") return;
    if (m.text().includes("ERR_CONNECTION_REFUSED")) offline.push(m.text());
    else errors.push(`console: ${m.text()}`);
  });
  return { errors, offline };
}

/** Opens [path] in [theme] and waits for the page to settle. */
export async function open(page: Page, path: string, theme: Theme = "light") {
  await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
  const res = await page.goto(path);
  await page.waitForLoadState("networkidle");
  return res;
}

// The API limits "who am I" checks to 10 a minute per account (personal/routes.ts statusLimits), and
// every full page load of a member page makes one. Signed-in tests therefore space page loads
// out (run them with --workers=1) instead of loosening a production limit.
let lastLoad = 0;
const loadGapMs = 6500;

/**
 * Opens a member page in [theme]. Signed-in pages hold live Firestore connections, so the
 * network never goes idle: wait for the DOM, then for [settle] ms (dev-server hydration, data).
 */
export async function openMember(page: Page, path: string, theme: Theme = "light", settle = 4500) {
  const wait = lastLoad + loadGapMs - Date.now();
  if (wait > 0) await page.waitForTimeout(wait);
  lastLoad = Date.now();
  await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
  const res = await page.goto(path, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(settle);
  await page.addStyleTag({ content: "nextjs-portal { display: none !important; }" });
  return res;
}

/**
 * Review picture of a signed-in screen: review/web/<screen>/<phase>-<width>-<theme>.png, where
 * phase is REVIEW_PHASE (before or after). Light and dark come from one page load: the theme
 * is "system", so switching the colour scheme restyles the page in place.
 */
export async function shootMember(page: Page, screen: string, path: string, suffix = "") {
  const phase = process.env.REVIEW_PHASE ?? "after";
  const width = page.viewportSize()!.width;
  await openMember(page, path, "light");
  for (const theme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
    await page.waitForTimeout(300);
    await page.screenshot({ path: `../../review/web/${screen}/${screen}_${width}_${theme}_${phase}${suffix}.png`, fullPage: false });
  }
}

/** WCAG 2.2 A/AA violations on the current page (axe-core). */
export async function axeViolations(page: Page) {
  const result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  return result.violations;
}

/** One line per violation, for readable failures and baselines. */
export function describeViolations(v: Awaited<ReturnType<typeof axeViolations>>) {
  return v.map((x) => `${x.impact ?? "?"} ${x.id}: ${x.nodes.length} element(s) ${x.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`);
}

/** Screenshot of the page in light and dark, compared with the stored ones. */
export async function expectScreens(page: Page, path: string, name: string) {
  for (const theme of ["light", "dark"] as const) {
    await open(page, path, theme);
    await expect(page).toHaveScreenshot(`${name}-${theme}.png`, { fullPage: true });
  }
}
