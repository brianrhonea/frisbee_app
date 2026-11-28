import { expect, test } from "@playwright/test";
import { openMember, watchErrors } from "./helpers";
import { ignorableConsole } from "./routeMap";
import { ensureYouthTeam, removeYouthTeam, teamIdByName } from "./worldApi";

test.afterAll(removeYouthTeam);

// N8 (signed in, synthetic world): what a member who is NOT on a team sees of its private areas, the
// sign-in and sign-up pages for someone already signed in, and the visitor-access rules for youth
// rosters and communities' members. Ada is signed in; Cascade Plain Team, the youth team and Cascade
// Open Group A are other people's.

test("a non-member opens a team's public page but is refused its chat and settings", async ({ page }) => {
  const id = await teamIdByName("Cascade Plain Team");
  const { errors } = watchErrors(page);
  await openMember(page, `/teams/${id}`);
  await expect(page.getByRole("heading", { level: 1, name: "Cascade Plain Team" })).toBeVisible();
  for (const [section, what] of [["chat", "chat"], ["settings", "settings"]] as const) {
    await openMember(page, `/teams/${id}/${section}`);
    await expect(page.getByText(`Only members see this team's ${what}.`)).toBeVisible();
    // Signed in, so no "Log in" nudge: there is nothing to log in to.
    await expect(page.locator("main").getByRole("link", { name: "Log in" })).toHaveCount(0);
  }
  expect(errors.filter((e) => !ignorableConsole.test(e))).toEqual([]);
});

test("a non-member of an approval-only community is refused its chat and does not see who is in it", async ({ page }) => {
  const id = await teamIdByName("Cascade Approval Group A");
  await openMember(page, `/teams/${id}/chat`);
  await expect(page.getByText("Only members see this community's chat.")).toBeVisible();
  await openMember(page, `/teams/${id}/roster`);
  await expect(page.getByText("Only members see who's in this community.")).toBeVisible();
});

test("a youth team's roster stays private to a non-member", async ({ page }) => {
  const id = await ensureYouthTeam();
  await openMember(page, `/teams/${id}/roster`);
  await expect(page.getByText("Rosters of youth teams are private: only members see them.")).toBeVisible();
});

test("a signed-in member who opens Log in or Sign up is moved on, to the destination when there is one", async ({ page }) => {
  await openMember(page, "/sign-in?next=%2Fschedule");
  await expect(page).toHaveURL(/\/schedule$/, { timeout: 20_000 });
  await openMember(page, "/sign-up?next=%2Fmessages");
  await expect(page).toHaveURL(/\/messages$/, { timeout: 20_000 });
  await openMember(page, "/sign-in");
  await expect(page).toHaveURL(/\/$/, { timeout: 20_000 });
});

// N10: members' Learn sits under Discover (UI-Q5). The unit tests pin the lists; this is the real shell.
test("Learn to play is under Discover for a member, and /learn keeps Discover highlighted", async ({ page }) => {
  const phone = page.viewportSize()!.width < 600;
  await openMember(page, "/learn");
  const nav = page.locator(phone ? "nav.tab-bar" : "nav.side-tabs");
  await expect(nav.getByRole("link", { name: "Discover" })).toHaveAttribute("aria-current", "page");
  if (phone) {
    // The bottom bar has the five tabs only; Learn is reached from Discover.
    await expect(nav.getByRole("link", { name: /^Learn/ })).toHaveCount(0);
  } else {
    // The sidebar lists Learn to play right under Discover, and it is the open page.
    const items = await nav.getByRole("link").evaluateAll((els) => els.map((e) => (e.textContent ?? "").trim()));
    expect(items.indexOf("Learn to play")).toBe(items.findIndex((t) => t.startsWith("Discover")) + 1);
    await expect(nav.getByRole("link", { name: "Learn to play" })).toHaveAttribute("aria-current", "page");
  }
});
