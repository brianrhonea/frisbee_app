import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { openMember, watchErrors } from "./helpers";
import { ignorableConsole } from "./routeMap";
import { api, personFor, teamIdByName, world } from "./worldApi";

// N11 (web half): the shared public links open the matching website page. The list is
// fixtures/shared_links.json, [{ "path": "/teams/{teamId}", "page": "team" }, ...], from the route map's
// section 5 (the website's form of each link). The app lane's list is packages/shared/fixtures/shared_links.json
// when it lands; the orchestrator unifies the two (same shape).
// Each link is opened signed in (Ada) and the page it names is checked: the same URL, no error screen, and
// what that page shows. Ids: the team, player, post and group are real; the tournament, meeting and
// division do not exist in the synthetic world (no tournaments are seeded), so those pages are checked
// for being the right page (the URL stays, the page does not crash) showing their "not found" or sign-in state.

type Link = { path: string; page: string };
const links = JSON.parse(readFileSync("tests/e2e/fixtures/shared_links.json", "utf8")) as Link[];

let memo: Promise<Record<string, string>> | null = null;
const ids = () => (memo ??= makeIds());
const makeIds = async () => {
  const w = world();
  const ada = await personFor(w.users.ada.email);
  const post = (await api(ada, "POST", "/v1/posts", { body: "A post to share, for the link test." })) as { id: string };
  return {
    teamId: w.teamId,
    uid: w.users.ada.uid,
    groupId: await teamIdByName("Cascade Open Group A"),
    postId: post.id,
    code: "ABC123",
    tournamentId: "tn1",
    divisionId: "d1",
    meetingId: "m1",
  } as Record<string, string>;
};

/** What each page shows when it opens (a real thing a person sees, not just "something rendered"). */
const shows: Record<string, (p: Page, id: Record<string, string>) => Promise<void>> = {
  team: (p) => expect(p.getByRole("heading", { level: 1, name: "Seattle Sidewinders" })).toBeVisible(),
  "team-roster": (p) => expect(p.getByRole("tablist", { name: "Roster sections" })).toBeVisible(),
  group: (p) => expect(p.locator("main")).toContainText(/community|Stall 10/i),
  invite: (p) => expect(p.locator("main")).toContainText(/invite|join|code/i),
  post: (p) => expect(p.getByText("A post to share, for the link test.").first()).toBeVisible(),
  "post-short": (p) => expect(p.locator("main")).toContainText(/post|Stall 10/i),
  player: (p) => expect(p.getByRole("heading", { name: /Ada Rivers/ }).first()).toBeVisible(),
  discover: (p) => expect(p.getByRole("radiogroup", { name: "Show" })).toBeVisible(),
  rankings: (p) => expect(p.getByRole("heading", { level: 1, name: /Rankings/i })).toBeVisible(),
  learn: (p) => expect(p.getByRole("heading", { level: 1 })).toBeVisible(),
};

test("the list has every link of the route map's section 5", () => {
  expect(links.map((l) => l.page)).toEqual(expect.arrayContaining(["team", "team-roster", "group", "invite", "post", "post-short", "player", "discover", "rankings", "tournament", "tournament-respond", "tournament-bracket", "tournament-live-draft", "meeting", "learn"]));
});

for (const link of links) {
  test(`${link.page}: ${link.path}`, async ({ page }) => {
    test.setTimeout(90_000);
    const id = await ids();
    const path = link.path.replace(/\{(\w+)\}/g, (_m, k: string) => id[k] ?? k);
    const { errors } = watchErrors(page);
    const res = await openMember(page, path, "light", 4000);
    expect(res?.status(), "status").toBeLessThan(500);
    const want = new URL(path, "http://x");
    const got = new URL(page.url());
    expect(got.pathname, "the same page").toBe(want.pathname);
    for (const [k, v] of want.searchParams) expect(got.searchParams.get(k), `?${k}`).toBe(v);
    await expect(page.locator("main").first()).toBeVisible();
    await expect(page.getByText("Something went wrong")).toHaveCount(0);
    await shows[link.page]?.(page, id);
    expect(errors.filter((e) => !ignorableConsole.test(e))).toEqual([]);
  });
}
