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

/** WCAG 2.2 A/AA violations on the current page (axe-core). */
export async function axeViolations(page: Page) {
  const result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  return result.violations;
}

/** One line per violation, for readable failures and baselines. */
export function describeViolations(v: Awaited<ReturnType<typeof axeViolations>>) {
  return v.map((x) => `${x.impact ?? "?"} ${x.id}: ${x.nodes.length} element(s)`);
}

/** Screenshot of the page in light and dark, compared with the stored ones. */
export async function expectScreens(page: Page, path: string, name: string) {
  for (const theme of ["light", "dark"] as const) {
    await open(page, path, theme);
    await expect(page).toHaveScreenshot(`${name}-${theme}.png`, { fullPage: true });
  }
}
