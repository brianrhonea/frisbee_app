import { expect, test } from "@playwright/test";
import { openMember } from "./helpers";

// H7 Chats (signed in, synthetic world): All, Teams, Direct and Unread filters over the inbox.
test("Chats: filters show team chats, direct messages or only what is unread", async ({ page }) => {
  await openMember(page, "/messages");
  const filters = page.getByRole("radiogroup", { name: "Show" });
  await expect(filters).toBeVisible();
  const teams = page.getByRole("list", { name: "Team chats" });
  await expect(teams.getByRole("listitem")).toHaveCount(3);
  await expect(page.getByRole("link", { name: /Ben Okafor/ })).toBeVisible();

  await filters.getByText("Teams").click();
  await expect(page.getByRole("link", { name: /Ben Okafor/ })).toHaveCount(0);
  await expect(page.getByRole("link", { name: /Seattle Sidewinders/ }).first()).toBeVisible();

  await filters.getByText("Direct").click();
  await expect(page.getByRole("link", { name: /Ben Okafor/ })).toBeVisible();
  await expect(teams).toHaveCount(0);

  // Ben's thread (2 unread) is unread, so Unread lists it and not a read team chat.
  await filters.getByText(/^Unread/).click();
  await expect(page.getByRole("link", { name: /Ben Okafor/ })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Conversations" }).getByRole("link", { name: /Capitol Hill Pickup Crew/ })).toHaveCount(0);
});
