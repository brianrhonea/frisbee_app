import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { axeViolations, describeViolations, openMember } from "./helpers";

// Sprint 5 R1 (website half): the "Team history" card on the player profile, signed in as Ada (the seeded
// world links her to the roster spot "Ada Rivers #1" on her team). The spec writes two stats games for that
// spot straight to the emulator (synthetic data, demo-stall10), one in 2026 and one in 2025, and removes
// them afterwards so no other spec sees them. At 375 and 1440 px, light and dark: nothing scrolls sideways
// and axe (WCAG 2.2 A/AA) finds nothing. Pictures: review/web/R1-team-history/ (REVIEW_PHASE before|after).
type World = { teamId: string; users: Record<"ada" | "ben" | "cam", { email: string; uid: string }> };
const world = () => JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as World;
test.setTimeout(240_000);
test.describe.configure({ mode: "serial" });

const FS = process.env.FIRESTORE_EMULATOR_HOST || process.env.E2E_FIRESTORE_HOST || "127.0.0.1:8080";
const docs = `http://${FS}/v1/projects/demo-stall10/databases/(default)/documents`;
const owner = { authorization: "Bearer owner", "content-type": "application/json" };

type V = Record<string, unknown>;
function enc(v: unknown): V {
  if (v === null) return { nullValue: null };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v as object).map(([k, x]) => [k, enc(x)])) } };
}

/** The id of the roster spot linked to [uid] on [teamId]. */
async function spotOf(teamId: string, uid: string): Promise<string> {
  const res = await fetch(`${docs}/teams/${teamId}:runQuery`, {
    method: "POST",
    headers: owner,
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: "roster" }], where: { fieldFilter: { field: { fieldPath: "userId" }, op: "EQUAL", value: { stringValue: uid } } }, limit: 1 } }),
  });
  const rows = (await res.json()) as { document?: { name: string } }[];
  const name = rows.find((r) => r.document)?.document?.name;
  if (!name) throw new Error("no linked roster spot for the user");
  return name.split("/").pop()!;
}

const gameIds = ["r1-g2026", "r1-g2025"];

test.beforeAll(async () => {
  const w = world();
  const spot = await spotOf(w.teamId, w.users.ada.uid);
  // The shared fixture's two games (2026-03-10 and 2025-06-01), the fixture's spot "a" being Ada's.
  const fixture = JSON.parse(readFileSync("../../packages/shared/fixtures/team_history/totals.json", "utf8")) as { games: V[] };
  const games = fixture.games.slice(0, 2).map((g, i) => ({ ...(JSON.parse(JSON.stringify(g).replaceAll('"a"', JSON.stringify(spot))) as V), id: gameIds[i] }));
  for (const g of games) {
    const { id, ...fields } = g;
    const res = await fetch(`${docs}/teams/${w.teamId}/statsGames/${id as string}`, { method: "PATCH", headers: owner, body: JSON.stringify({ fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, enc(v)])) }) });
    if (!res.ok) throw new Error(`seed game ${id as string}: ${await res.text()}`);
  }
});

test.afterAll(async () => {
  const w = world();
  for (const id of gameIds) await fetch(`${docs}/teams/${w.teamId}/statsGames/${id}`, { method: "DELETE", headers: owner });
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

test("R1 own profile: Team history with the spot, the latest season, and Show all seasons", async ({ page }) => {
  const w = world();
  await openMember(page, `/players/${w.users.ada.uid}`);
  const card = page.getByRole("region", { name: "Team history" });
  await expect(card).toBeVisible({ timeout: 30_000 });
  await expect(card.getByText("Ada Rivers · #1")).toBeVisible();
  // Not a Past team: Ada is on it.
  await expect(card.getByText("Past")).toHaveCount(0);
  await expect(card.locator(".th-season-list li")).toHaveCount(1);
  await expect(card.locator(".th-season-list li").first()).toContainText("2026");
  await noSideScroll(page);
  await axeBothThemes(page, "R1 collapsed");
  const toggle = card.getByRole("button", { name: "Show all seasons (2)" });
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await toggle.click();
  await expect(card.locator(".th-season-list li")).toHaveCount(2);
  await expect(card.locator(".th-season-list li").nth(1)).toContainText("2025");
  await expect(card.getByRole("button", { name: "Hide other seasons" })).toHaveAttribute("aria-expanded", "true");
  await noSideScroll(page);
  await axeBothThemes(page, "R1 expanded");
});

test("R1 someone else's profile without history shows no card", async ({ page }) => {
  const w = world();
  await openMember(page, `/players/${w.users.ben.uid}`);
  await expect(page.getByRole("heading", { name: "Posts" })).toBeVisible();
  await page.waitForTimeout(1500);
  await expect(page.getByRole("region", { name: "Team history" })).toHaveCount(0);
  await expect(page.getByRole("heading", { name: "Team history" })).toHaveCount(0);
  await noSideScroll(page);
});

test("pictures: Team history on your profile", async ({ page }) => {
  const phase = process.env.REVIEW_PHASE ?? "after";
  const w = world();
  await openMember(page, `/players/${w.users.ada.uid}`);
  if (phase === "after") await expect(page.getByRole("region", { name: "Team history" })).toBeVisible({ timeout: 30_000 });
  else await page.waitForTimeout(3000);
  const width = page.viewportSize()!.width;
  for (const theme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme: theme, reducedMotion: "reduce" });
    await page.waitForTimeout(300);
    await page.screenshot({ path: `../../review/web/R1-team-history/R1-team-history_${width}_${theme}_${phase}.png`, fullPage: true });
  }
});
