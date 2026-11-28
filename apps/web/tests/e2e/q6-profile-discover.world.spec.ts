import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { axeViolations, describeViolations, openMember } from "./helpers";

// Sprint 5 Q6 (website half; the app's mirror is test/ui/q6_app_test.dart): the "…" menu over the profile cover
// (Report, Block, Share), the Media tab, and Discover's Events chip and Athletes chip, signed in as Ada. The spec
// writes one post with a photo for Ben straight to the emulator (synthetic data, demo-stall10) and removes it
// afterwards. At 375 and 1440 px, light and dark: nothing scrolls sideways and axe (WCAG 2.2 A/AA) finds nothing,
// with the menu open as well. Pictures: review/web/Q6/ (REVIEW_PHASE before|after).
type World = { teamId: string; users: Record<"ada" | "ben" | "cam", { email: string; uid: string }> };
const world = () => JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as World;
test.setTimeout(240_000);
test.describe.configure({ mode: "serial" });

const FS = process.env.FIRESTORE_EMULATOR_HOST || process.env.E2E_FIRESTORE_HOST || "127.0.0.1:8080";
const docs = `http://${FS}/v1/projects/demo-stall10/databases/(default)/documents`;
const owner = { authorization: "Bearer owner", "content-type": "application/json" };
const postId = "q6-media-post";

test.beforeAll(async () => {
  const w = world();
  const now = new Date().toISOString();
  const fields = {
    authorId: { stringValue: w.users.ben.uid },
    authorName: { stringValue: "Ben Okafor" },
    body: { stringValue: "Q6 photo post" },
    private: { booleanValue: false },
    createdAt: { timestampValue: now },
    likedBy: { arrayValue: { values: [] } },
    repostedBy: { arrayValue: { values: [] } },
    commentCount: { integerValue: "0" },
    images: {
      arrayValue: {
        values: [
          {
            mapValue: {
              fields: {
                path: { stringValue: "posts/q6/a.jpg" },
                name: { stringValue: "a.jpg" },
                contentType: { stringValue: "image/jpeg" },
                size: { integerValue: "10" },
              },
            },
          },
        ],
      },
    },
  };
  const res = await fetch(`${docs}/posts/${postId}`, { method: "PATCH", headers: owner, body: JSON.stringify({ fields }) });
  if (!res.ok) throw new Error(`seed post: ${await res.text()}`);
});

test.afterAll(async () => {
  await fetch(`${docs}/posts/${postId}`, { method: "DELETE", headers: owner });
});

async function noSideScroll(page: Page) {
  const wide = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(wide, "horizontal scroll").toBeLessThanOrEqual(0);
}

async function axeBothThemes(page: Page, name: string) {
  for (const theme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
    await page.waitForTimeout(300);
    expect(describeViolations(await axeViolations(page)), `${name} ${theme}`).toEqual([]);
  }
}

test("Q6 profile menu: Report, Block, Share in order, keyboard and screen-reader operable", async ({ page }) => {
  const w = world();
  await openMember(page, `/players/${w.users.ben.uid}`);
  const cover = page.locator(".ui-cover");
  const button = cover.getByRole("button", { name: "More options" });
  await expect(button).toBeVisible({ timeout: 30_000 });
  await expect(button).toHaveAttribute("aria-haspopup", "menu");
  await expect(button).toHaveAttribute("aria-expanded", "false");
  // The ghost buttons under the details are gone.
  await expect(page.locator(".profile-safety, .profile-secondary")).toHaveCount(0);
  // Keyboard: focus the button, Down opens on the first item, Down moves, Escape closes and returns.
  await button.focus();
  await page.keyboard.press("ArrowDown");
  const items = page.getByRole("menu").getByRole("menuitem");
  await expect(items).toHaveText(["Report", "Block", "Share"]);
  await expect(items.first()).toBeFocused();
  await page.keyboard.press("ArrowDown");
  await expect(items.nth(1)).toBeFocused();
  await noSideScroll(page);
  await axeBothThemes(page, "Q6 menu open");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("menu")).toHaveCount(0);
  await expect(button).toBeFocused();
  // Report opens the report dialog.
  await button.click();
  await page.getByRole("menuitem", { name: "Report" }).click();
  await expect(page.getByRole("dialog", { name: "Report this profile" })).toBeVisible();
  await page.keyboard.press("Escape");
  await noSideScroll(page);
});

test("Q6 your own profile: the menu holds Share only", async ({ page }) => {
  const w = world();
  await openMember(page, `/players/${w.users.ada.uid}`);
  await page.locator(".ui-cover").getByRole("button", { name: "More options" }).click();
  await expect(page.getByRole("menuitem")).toHaveText(["Share"]);
  await expect(page.locator(".ui-cover").getByRole("link", { name: "Edit profile" })).toBeVisible();
  await page.keyboard.press("Escape");
});

test("Q6 Media tab: the photos of the posts the page already lists, opening the post", async ({ page }) => {
  const w = world();
  await openMember(page, `/players/${w.users.ben.uid}`);
  await expect(page.getByRole("tab", { name: "Posts" })).toHaveAttribute("aria-selected", "true", { timeout: 30_000 });
  await page.getByRole("tab", { name: "Media" }).click();
  await expect(page.getByRole("heading", { name: "Media" })).toBeVisible();
  // The link is named by its photo (its alt text), or by "Photo unavailable" when the emulator has no file.
  const tiles = page.locator(".media-grid .media-tile");
  await expect(tiles).toHaveCount(1, { timeout: 30_000 });
  await expect(tiles.first()).toHaveAttribute("href", `/posts/${postId}`);
  await page.waitForTimeout(600);
  await noSideScroll(page);
  await axeBothThemes(page, "Q6 media");
});

test("Q6 Media tab: someone with no photos sees the empty state", async ({ page }) => {
  const w = world();
  await openMember(page, `/players/${w.users.cam.uid}`);
  await page.getByRole("tab", { name: "Media" }).click({ timeout: 30_000 });
  await expect(page.getByText("No photos or videos yet.")).toBeVisible();
  await page.waitForTimeout(600);
  await noSideScroll(page);
  await axeBothThemes(page, "Q6 media empty");
});

test("Q6 Discover: Events chip after All, Athletes instead of Players, nothing scrolls sideways", async ({ page }) => {
  await openMember(page, "/explore");
  const chips = page.getByRole("radiogroup", { name: "Show" }).getByRole("radio");
  await expect(chips.first()).toBeVisible({ timeout: 30_000 });
  const names = await chips.allInnerTexts();
  expect(names.slice(0, 3)).toEqual(["All", "Events", "Tournaments"]);
  expect(names.at(-1)).toBe("Athletes");
  expect(names).not.toContain("Players");
  await page.getByRole("radio", { name: "Events" }).click();
  await expect(page.getByRole("radio", { name: "Events" })).toBeChecked();
  await expect(page).toHaveURL(/only=events/);
  // The same events Discover lists under All: the Coming up section.
  await expect(page.getByRole("heading", { name: "Coming up" })).toBeVisible();
  await noSideScroll(page);
  await axeBothThemes(page, "Q6 Discover Events");
  await page.getByRole("radio", { name: "Athletes" }).click();
  await expect(page).toHaveURL(/only=players/);
  await noSideScroll(page);
});

test("pictures: Q6 profile menu, Media tab and Discover chips", async ({ page }) => {
  const phase = process.env.REVIEW_PHASE ?? "after";
  const w = world();
  const width = page.viewportSize()!.width;
  const shot = async (name: string) => {
    for (const theme of ["light", "dark"] as const) {
      await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
      await page.waitForTimeout(300);
      await page.screenshot({ path: `../../review/web/Q6/Q6-${name}_${width}_${theme}_${phase}.png`, fullPage: true });
    }
  };
  await openMember(page, `/players/${w.users.ben.uid}`);
  await page.waitForTimeout(3000);
  await shot("profile");
  if (phase === "after") {
    await page.locator(".ui-cover").getByRole("button", { name: "More options" }).click();
    await shot("profile-menu");
    await page.keyboard.press("Escape");
    await page.getByRole("tab", { name: "Media" }).click();
    await page.waitForTimeout(1500);
    await shot("profile-media");
  }
  await openMember(page, "/explore");
  await page.waitForTimeout(2000);
  await shot("discover");
});
