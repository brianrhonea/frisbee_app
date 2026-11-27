import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import { open } from "./helpers";

// The website shell (Sprint 3 S3, N9): sidebar from 900 px, an icon rail from
// 600 to 899, the tabs as a bottom bar under 600, the page capped at 1600 px.
// Signed out (visitors keep Learn as a tab; members' order is unit-tested in
// tests/unit/AppFrame.test.tsx).

/** Clicks a link once the dev server has hydrated the page, and waits out the dev compile of the next one. */
async function clickAndWait(page: import("@playwright/test").Page, link: import("@playwright/test").Locator, url: RegExp) {
  await page.waitForTimeout(2500);
  await link.click();
  await expect(page).toHaveURL(url, { timeout: 30_000 });
}

const pagesToCheck = ["/", "/explore", "/learn", "/sign-in", "/tournaments", "/teams"];

/** Which navigation shows, from what the browser lays out. */
async function shell(page: import("@playwright/test").Page) {
  return page.evaluate(() => {
    const shown = (sel: string) => {
      const el = document.querySelector(sel);
      if (!el) return false;
      const r = el.getBoundingClientRect();
      return getComputedStyle(el).display !== "none" && r.width > 0 && r.height > 0;
    };
    const side = document.querySelector(".side-nav")?.getBoundingClientRect();
    return {
      sidebar: shown(".side-nav"),
      sideWidth: side ? Math.round(side.width) : 0,
      bottom: shown(".tab-bar"),
      aside: shown(".frame-aside"),
      overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      labels: shown(".side-nav .side-label"),
    };
  });
}

test("the navigation fits the width and nothing scrolls sideways", async ({ page }, info) => {
  const w = page.viewportSize()!.width;
  for (const path of pagesToCheck) {
    await open(page, path);
    const s = await shell(page);
    expect(s.overflow, `${path} at ${w}`).toBeLessThanOrEqual(0);
    if (w >= 900) expect(s, `${path} at ${w}`).toMatchObject({ sidebar: true, bottom: false, labels: true, sideWidth: 236 });
    else if (w >= 600) expect(s, `${path} at ${w}`).toMatchObject({ sidebar: true, bottom: false, labels: false, sideWidth: 76 });
    else expect(s, `${path} at ${w}`).toMatchObject({ sidebar: false, bottom: true });
    // Exactly one of the two navigations is usable at a time.
    expect(s.sidebar !== s.bottom, `${path} at ${w}`).toBe(true);
  }
  void info;
});

test("each tab opens its page (visitors)", async ({ page }) => {
  await open(page, "/explore");
  const w = page.viewportSize()!.width;
  const nav = page.locator(w < 600 ? ".tab-bar" : ".side-tabs");
  const tabs = await nav.getByRole("link").evaluateAll((els) => els.map((e) => [e.textContent?.trim(), e.getAttribute("href")]));
  expect(tabs).toEqual([
    ["Discover", "/explore"],
    ["Tournaments", "/tournaments"],
    ["Pickup", "/explore?only=pickup"],
    ["Communities", "/explore?only=groups"],
    ["Learn", "/learn"],
  ]);
  await clickAndWait(page, nav.getByRole("link", { name: "Tournaments" }), /\/tournaments$/);
  await expect(nav.getByRole("link", { name: "Tournaments" })).toHaveAttribute("aria-current", "page");
});

test("Discover has a clear way to Learn, and /learn still opens", async ({ page }) => {
  await open(page, "/explore");
  await clickAndWait(page, page.getByRole("link", { name: /New to ultimate/ }), /\/learn$/);
  await expect(page.locator("main").first()).toBeVisible();
});

test("the account area is the picture or the Log in link at the top right", async ({ page }) => {
  await open(page, "/explore");
  const bar = page.locator(".top-bar");
  await expect(bar.getByRole("link", { name: /Log in|Join free/ }).first()).toBeVisible();
  const box = await bar.locator(".header-actions").boundingBox();
  const w = page.viewportSize()!.width;
  expect(box!.x + box!.width).toBeGreaterThan(w - 40);
});

test("axe: the shell has no violations (light and dark)", async ({ page }) => {
  for (const theme of ["light", "dark"] as const) {
    await open(page, "/explore", theme);
    const result = await new AxeBuilder({ page })
      .include(".skip-link")
      .include(".top-bar")
      .include(".side-nav")
      .include(".tab-bar")
      .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
      .analyze();
    expect(result.violations.map((v) => `${theme} ${v.id}: ${v.nodes.map((n) => n.target.join(" ")).join(", ")}`)).toEqual([]);
  }
});

test("Back returns to the same scroll position", async ({ page }) => {
  await open(page, "/explore");
  await page.evaluate(() => window.scrollTo(0, 400));
  const before = await page.evaluate(() => window.scrollY);
  expect(before).toBeGreaterThan(100);
  await clickAndWait(page, page.locator("footer a", { hasText: "About" }), /\/about$/);
  await page.goBack();
  await expect(page).toHaveURL(/\/explore$/);
  await expect.poll(() => page.evaluate(() => window.scrollY), { timeout: 5000 }).toBeGreaterThan(before - 60);
});

test("the bottom bar never covers the end of the page", async ({ page }) => {
  const w = page.viewportSize()!.width;
  test.skip(w >= 600, "phones only");
  await open(page, "/explore");
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
  const gap = await page.evaluate(() => {
    const bar = document.querySelector(".tab-bar")!.getBoundingClientRect();
    const foot = document.querySelector("footer.site-footer")!.getBoundingClientRect();
    return bar.top - foot.bottom;
  });
  expect(gap).toBeGreaterThanOrEqual(-1);
});

test("floating and sticky bars at the foot sit above the bottom tab bar", async ({ page }) => {
  test.skip(page.viewportSize()!.width >= 600, "phones only");
  await open(page, "/explore");
  // Members' floating Post button and the voice bar only exist signed in; stand-ins
  // with their classes get the same CSS. (The game, stats and whiteboard bars load
  // their CSS with their pages; tests/unit/shellCss.test.ts checks their offsets.)
  const gaps = await page.evaluate(() => {
    const frame = document.querySelector(".frame")!;
    const hub = document.createElement("div");
    hub.className = "team-hub";
    frame.append(hub);
    const make = (cls: string, parent: Element = frame) => {
      const el = document.createElement("div");
      el.className = cls;
      el.textContent = cls;
      parent.append(el);
      return el;
    };
    const bar = document.querySelector(".tab-bar")!.getBoundingClientRect().top;
    const els = [make("fab-post"), make("voice-bar")];
    return els.map((el) => [el.className, Math.round(bar - el.getBoundingClientRect().bottom)] as const);
  });
  for (const [cls, gap] of gaps) expect(gap, cls).toBeGreaterThanOrEqual(0);
});

// Breakpoint edges, one project is enough: the media queries do not depend on it.
test.describe("breakpoint edges", () => {
  test.beforeEach(({}, info) => test.skip(info.project.name !== "laptop", "edges run once"));
  const edges: [number, "bottom" | "rail" | "side", boolean][] = [
    [599, "bottom", false],
    [600, "rail", false],
    [899, "rail", false],
    [900, "side", false],
    [1199, "side", false],
    [1200, "side", true],
  ];
  for (const [w, kind, aside] of edges) {
    test(`${w} px shows ${kind}${aside ? " and the context panel" : ""}`, async ({ page }) => {
      await page.setViewportSize({ width: w, height: 800 });
      // /rankings has the right column (Home and team pages have their own).
      await open(page, "/explore");
      const s = await shell(page);
      expect(s.overflow).toBeLessThanOrEqual(0);
      expect(s.bottom).toBe(kind === "bottom");
      expect(s.sidebar).toBe(kind !== "bottom");
      if (kind === "rail") expect(s.sideWidth).toBe(76);
      if (kind === "side") expect(s.sideWidth).toBe(236);
      expect(s.aside).toBe(aside);
    });
  }

  test("1920 px: the page is capped at 1600 px", async ({ page }) => {
    await page.setViewportSize({ width: 1920, height: 900 });
    await open(page, "/explore");
    const w = await page.locator(".frame").evaluate((el) => Math.round(el.getBoundingClientRect().width));
    expect(w).toBeLessThanOrEqual(1600);
    expect(w).toBeGreaterThan(1500);
    // The right panel stays with the page, not at the far edge of the window.
    const aside = await page.locator(".frame-aside").evaluate((el) => Math.round(el.getBoundingClientRect().right));
    expect(aside).toBeLessThanOrEqual(1760);
    expect((await shell(page)).overflow).toBeLessThanOrEqual(0);
  });
});
