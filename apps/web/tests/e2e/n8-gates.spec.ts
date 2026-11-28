import { expect, test } from "@playwright/test";
import { open, watchErrors } from "./helpers";
import { ignorableConsole } from "./routeMap";

// N8 (signed out): who may open what (docs/specifications/navigation-route-map.md section 4).
// On the website a member-only page does not bounce the visitor with an HTTP redirect: it shows a
// "Join Stall 10 to see this" card whose Log in and Sign up links carry `?next=<this page>`, and
// signing in comes back to it. These tests pin that behaviour, and that the pages visitors may see
// (Learn, events, teams, tournaments, Discover, rankings) do not ask them to join.

/** Member-only pages (client-gated, so they need no API): path and the part of the card's text that names it. */
const memberOnly = [
  "/schedule",
  "/messages",
  "/notifications",
  "/notifications/requests",
  "/settings/profile",
  "/settings/privacy",
  "/settings/account",
  "/teams/new",
  "/tournaments/host",
  "/tournaments/t1/enter",
  "/players/u1",
  "/staff",
  "/payments/payouts",
];

for (const path of memberOnly) {
  test(`${path}: a visitor is asked to log in and comes back here`, async ({ page }) => {
    const { errors } = watchErrors(page);
    await open(page, path);
    await expect(page.locator("main").first()).toBeVisible();
    const card = page.locator(".join-prompt");
    await expect(card).toBeVisible();
    const next = encodeURIComponent(path);
    await expect(card.getByRole("link", { name: "Log in" })).toHaveAttribute("href", `/sign-in?next=${next}`);
    await expect(card.getByRole("link", { name: /Sign up/ })).toHaveAttribute("href", `/sign-up?next=${next}`);
    expect(errors.filter((e) => !ignorableConsole.test(e))).toEqual([]);
  });
}

// The host form's own link carries its defaults (Host a tournament opens it with `?host=&type=tournament`).
test("/tournaments/new: the card keeps the form's own query as the destination", async ({ page }) => {
  await open(page, "/tournaments/new");
  const next = encodeURIComponent("/tournaments/new?host=&type=tournament");
  await expect(page.locator(".join-prompt").getByRole("link", { name: "Log in" })).toHaveAttribute("href", `/sign-in?next=${next}`);
});

test("the Log in link opens the sign-in page with the destination (the form itself is in the signed-in suite)", async ({ page }) => {
  await open(page, "/schedule");
  await page.locator(".join-prompt").getByRole("link", { name: "Log in" }).click();
  await expect(page).toHaveURL(/\/sign-in\?next=%2Fschedule$/);
});

test("/profile sends a visitor to sign in and keeps /profile as the destination", async ({ page }) => {
  await page.goto("/profile");
  await expect(page).toHaveURL(/\/sign-in\?next=\/profile$/, { timeout: 30_000 });
});

test("/home is Home", async ({ page }) => {
  await page.goto("/home");
  await expect(page).toHaveURL(/\/$/);
});

/** Pages a signed-out visitor may use (the visitor-access rule): no join card, real content. */
const visitorOpen = ["/learn", "/explore", "/explore?only=teams", "/tournaments", "/teams", "/rankings", "/get-the-app", "/about", "/sign-in", "/sign-up"];

for (const path of visitorOpen) {
  test(`${path}: open to visitors, no "Join to see this" card`, async ({ page }) => {
    const { errors } = watchErrors(page);
    const res = await open(page, path);
    expect(res?.status()).toBeLessThan(500);
    await expect(page.locator("main").first()).toBeVisible();
    if (path !== "/tournaments") await expect(page.locator(".join-prompt")).toHaveCount(0); // (the list has its own sign-up note, a call to action)
    await expect(page).toHaveURL(new RegExp(path.replace(/[?]/g, "\\?") + "$"));
    expect(errors.filter((e) => !ignorableConsole.test(e))).toEqual([]);
  });
}
