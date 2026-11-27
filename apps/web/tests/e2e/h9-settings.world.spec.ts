import { expect, test } from "@playwright/test";
import { openMember } from "./helpers";

// H9 Settings (signed in, synthetic world): the sections in groups (no repeated entry), the profile
// row, the profile card laid out under its header, Appearance in Account, and the delete flow's entry.
test("Settings: grouped sections, each once, with the profile row", async ({ page }) => {
  await openMember(page, "/settings/profile");
  const nav = page.getByRole("navigation", { name: "Settings" });
  const labels = await nav.locator(".settings-group a").evaluateAll((els) => els.map((e) => e.textContent?.replace("›", "").trim()));
  expect(labels).toEqual(["Profile", "Personal details", "Privacy", "Notifications", "Calendars", "People you follow", "Blocked accounts", "Account", "Help", "Learn to play"]);
  await expect(nav.getByRole("link", { name: "Profile", exact: true })).toHaveAttribute("aria-current", "page");
  // The identity card keeps its photo header: the avatar sits below the header image, not under it.
  const card = page.locator(".identity-card");
  await expect(card).toBeVisible();
  const header = await page.locator(".identity-header").boundingBox();
  const cardBox = await card.boundingBox();
  expect(Math.abs(header!.x - cardBox!.x)).toBeLessThan(2);
});

test("Settings: Appearance (Light, Dark, System) is in Account, and Delete account is reachable", async ({ page }) => {
  await openMember(page, "/settings/account");
  await expect(page.getByRole("heading", { name: /Appearance/ })).toBeVisible();
  for (const t of ["Light", "Dark", "System"]) await expect(page.getByRole("main").getByText(t, { exact: true }).first()).toBeVisible();
  await expect(page.getByRole("link", { name: /Delete (your )?account/i }).first()).toBeVisible();
});
