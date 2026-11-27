import { expect, test } from "@playwright/test";
import { open } from "./helpers";

// N10: the shell by keyboard. A skip link is the first stop and moves to the
// page; Tab visits the bars in reading order (skip link, top bar, navigation,
// page, footer; the phone tab bar last); a hidden navigation is never focused;
// the focused control always shows a ring; arrows move through chips and tabs.

/** The landmark a focused element sits in. */
async function where(page: import("@playwright/test").Page) {
  return page.evaluate(() => {
    const el = document.activeElement as HTMLElement | null;
    // Past the last stop: the document itself, or the dev server's own overlay.
    if (!el || el === document.body || el === document.documentElement || el.closest("nextjs-portal")) return { zone: "body", visible: false, ring: false, label: "" };
    const r = el.getBoundingClientRect();
    const zone = el.classList.contains("skip-link") ? "skip" : el.closest("header.top-bar") ? "top" : el.closest("nav.tab-bar") ? "tabbar" : el.closest(".side-nav") ? "side" : el.closest("footer") ? "footer" : el.closest("main") ? "main" : el.closest("aside.frame-aside") ? "aside" : "other";
    const cs = getComputedStyle(el);
    const drawn = (c: CSSStyleDeclaration) => c.outlineStyle !== "none" && parseFloat(c.outlineWidth) >= 2;
    // Tabs and chips draw the ring on their face (a 48 px target around a smaller pill).
    const face = el.querySelector(".ui-face");
    const ring = drawn(cs) || (!!face && drawn(getComputedStyle(face)));
    return { zone, visible: r.width > 0 && r.height > 0, ring, label: (el.getAttribute("aria-label") || el.textContent || "").trim().slice(0, 30) };
  });
}

test("the skip link is the first stop, shows itself and moves focus to the page", async ({ page }) => {
  await open(page, "/explore");
  await page.waitForTimeout(1500);
  await page.keyboard.press("Tab");
  const skip = page.getByRole("link", { name: "Skip to content" });
  await expect(skip).toBeFocused();
  const box = await skip.boundingBox();
  expect(box!.y).toBeGreaterThanOrEqual(0);
  expect((await where(page)).ring).toBe(true);
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/#main$/);
  expect(await page.evaluate(() => document.activeElement?.id)).toBe("main");
  // The next Tab goes into the page, not back up to the bars.
  await page.keyboard.press("Tab");
  expect(["main", "aside", "footer"]).toContain((await where(page)).zone);
});

test("Tab visits the shell in reading order, never lands on a hidden control and always shows a ring", async ({ page }) => {
  await open(page, "/explore");
  await page.waitForTimeout(1500);
  const phone = page.viewportSize()!.width < 600;
  // The right panel follows the footer in the DOM (it is a sibling of the page column).
  const order = ["skip", "top", "side", "main", "footer", "aside", "tabbar"];
  const seen: string[] = [];
  for (let i = 0; i < 90; i++) {
    await page.keyboard.press("Tab");
    const w = await where(page);
    if (w.zone === "body") break; // past the last stop
    expect(w.visible, `${w.zone} "${w.label}" is hidden`).toBe(true);
    expect(w.ring, `${w.zone} "${w.label}" has no focus ring`).toBe(true);
    if (seen[seen.length - 1] !== w.zone) seen.push(w.zone);
  }
  // Zones appear in reading order (each at most once, as bars are contiguous in the DOM).
  const idx = seen.map((z) => order.indexOf(z));
  expect(idx, seen.join(" > ")).toEqual([...idx].sort((a, b) => a - b));
  expect(seen[0]).toBe("skip");
  expect(seen).toContain("top");
  if (phone) {
    expect(seen).not.toContain("side");
    expect(seen).toContain("tabbar");
  } else {
    expect(seen).toContain("side");
    expect(seen).not.toContain("tabbar");
  }
});

test("only the navigation that is showing is reachable", async ({ page }) => {
  await open(page, "/explore");
  const phone = page.viewportSize()!.width < 600;
  const hidden = page.locator(phone ? ".side-nav a" : "nav.tab-bar a");
  for (const h of await hidden.all()) await expect(h).toBeHidden();
});

test("the navigation links are real links with the current page marked", async ({ page }) => {
  await open(page, "/explore");
  const phone = page.viewportSize()!.width < 600;
  const nav = page.locator(phone ? "nav.tab-bar" : "nav.side-tabs");
  await expect(nav.getByRole("link", { name: "Discover" })).toHaveAttribute("aria-current", "page");
  await expect(nav.locator('[aria-current="page"]')).toHaveCount(1);
});

test("chips on Discover: arrows move and select, Home and End jump", async ({ page }) => {
  await open(page, "/explore");
  await page.waitForTimeout(2000);
  const group = page.getByRole("radiogroup", { name: "Show" });
  const radios = group.getByRole("radio");
  const n = await radios.count();
  expect(n).toBeGreaterThan(3);
  await radios.first().focus();
  await page.keyboard.press("ArrowRight");
  await expect(radios.nth(1)).toBeFocused();
  await expect(radios.nth(1)).toBeChecked();
  await page.keyboard.press("End");
  await expect(radios.nth(n - 1)).toBeChecked();
  await page.keyboard.press("Home");
  await expect(radios.first()).toBeChecked();
});

test("the gallery's tablist: arrows, Home and End (the shared tabs)", async ({ page }) => {
  test.skip(!!process.env.E2E_BASE_URL, "the gallery is not served by production builds");
  await open(page, "/dev/ui");
  await page.waitForTimeout(1500);
  const list = page.getByRole("tablist", { name: "Many tabs, scrolling" });
  const tabs = list.getByRole("tab");
  await list.getByRole("tab", { selected: true }).focus();
  await page.keyboard.press("Home");
  await expect(tabs.first()).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("ArrowRight");
  await expect(tabs.nth(1)).toBeFocused();
  await page.keyboard.press("ArrowLeft");
  await expect(tabs.first()).toBeFocused();
  await page.keyboard.press("End");
  await expect(tabs.last()).toHaveAttribute("aria-selected", "true");
});
