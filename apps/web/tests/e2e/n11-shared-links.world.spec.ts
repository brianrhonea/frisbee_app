import { expect, test, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { openMember, watchErrors } from "./helpers";
import { ignorableConsole } from "./routeMap";
import { api, personFor, teamIdByName, world } from "./worldApi";

// N11 (web half): the shared public links open the matching website page. The one list is
// packages/shared/fixtures/shared_links.json, which the app's test opens on its router too: each case's `path`
// is the link people share and `web` is the website route it must end on. Each link is opened signed in (Ada)
// and the page it names is checked: the URL (after any redirect), no error screen, and what that page shows.
// The fixture's ids (t1, p1, u2, x1, d1, m1) stand for real ones here: the team, player, post and group are real;
// the tournament, meeting and division do not exist in the synthetic world (no tournaments are seeded), so
// those pages are checked for being the right page (the URL stays, the page does not crash) showing their
// "not found" or sign-in state.

type Case = { name: string; path: string; page: string; appRoute: string; web: string };
const { cases } = JSON.parse(readFileSync("../../packages/shared/fixtures/shared_links.json", "utf8")) as { cases: Case[] };

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
    tournamentId: "tn1",
    divisionId: "d1",
    meetingId: "m1",
  } as Record<string, string>;
};

/** The fixture's stand-in ids for the real ones; a group's link (/g/) uses the group in place of the team. */
const real = (path: string, id: Record<string, string>) =>
  path.replace(/\b(t1|p1|u2|x1|d1|m1)\b/g, (m) => ({ t1: path.startsWith("/g/") ? id.groupId : id.teamId, p1: id.postId, u2: id.uid, x1: id.tournamentId, d1: id.divisionId, m1: id.meetingId })[m]!);

/**
 * The website route a case must end on: its `web` pattern with the real ids of the link's own path segments,
 * in order ("/teams/[team]/meetings/[id]" from "/team-meetings/t1/m1"). Brackets with no id left stay as they are.
 */
function endsOn(c: Case, id: Record<string, string>): string {
  const pathOnly = c.path.split("?")[0]!;
  const fixture = pathOnly.split("/").filter(Boolean);
  const own = real(pathOnly, id)
    .split("/")
    .filter(Boolean)
    .filter((_s, i) => /^(t1|p1|u2|x1|d1|m1|ABC234)$/.test(fixture[i]!));
  let n = 0;
  return c.web.replace(/\[[^\]]+\]/g, (m) => own[n++] ?? m);
}

/** Where the website itself serves a case whose app path has no equal route on it (the route map's section 5). */
const websiteUrl: Record<string, (id: Record<string, string>) => string> = {
  bracket: (id) => `/tournaments/${id.tournamentId}/bracket?division=${id.divisionId}`,
  meeting: (id) => `/teams/${id.teamId}/meetings/${id.meetingId}`,
};

/** What each page shows when it opens (a real thing a person sees, not just "something rendered"). */
const shows: Record<string, (p: Page, id: Record<string, string>) => Promise<void>> = {
  team: (p) => expect(p.getByRole("heading", { level: 1, name: "Seattle Sidewinders" })).toBeVisible(),
  "team section": (p) => expect(p.getByRole("tablist", { name: "Roster sections" })).toBeVisible(),
  group: (p) => expect(p.locator("main")).toContainText(/community|Stall 10/i),
  invite: (p) => expect(p.locator("main")).toContainText(/invite|join|code/i),
  post: (p) => expect(p.getByText("A post to share, for the link test.").first()).toBeVisible(),
  "post short link": (p) => expect(p.locator("main")).toContainText(/post|Stall 10/i),
  player: (p) => expect(p.getByRole("heading", { name: /Ada Rivers/ }).first()).toBeVisible(),
  "discover filter": (p) => expect(p.getByRole("radiogroup", { name: "Show" })).toBeVisible(),
  rankings: (p) => expect(p.getByRole("heading", { level: 1, name: /Rankings/i })).toBeVisible(),
  "learn rules": (p) => expect(p.getByRole("heading", { level: 1 })).toBeVisible(),
  "old rules link": (p) => expect(p.getByRole("heading", { level: 1 })).toBeVisible(),
};

test("the list has every kind of link the app shares", () => {
  expect(cases.map((c) => c.page)).toEqual(expect.arrayContaining(["team", "invite", "post", "player", "explore", "rankings", "tournament", "respond", "bracket", "liveDraft", "meeting", "learn"]));
  expect(cases.some((c) => c.path.includes("?section="))).toBe(true);
});

for (const c of cases) {
  test(`${c.name}: ${c.path}`, async ({ page }) => {
    test.setTimeout(90_000);
    const id = await ids();
    const fixed = websiteUrl[c.page] as ((id: Record<string, string>) => string) | undefined;
    const path = fixed ? fixed(id) : real(c.path, id);
    const { errors } = watchErrors(page);
    const res = await openMember(page, path, "light", 4000);
    expect(res?.status(), "status").toBeLessThan(500);
    const want = new URL(fixed ? path : endsOn(c, id) + (c.path.includes("?") ? "?" + real(c.path, id).split("?")[1] : ""), "http://x");
    const got = new URL(page.url());
    expect(got.pathname, "the page it ends on").toBe(want.pathname);
    // The link's own filters stay (a section name is spent on the redirect).
    if (!fixed) for (const [k, v] of want.searchParams) if (k !== "section") expect(got.searchParams.get(k), `?${k}`).toBe(v);
    await expect(page.locator("main").first()).toBeVisible();
    await expect(page.getByText("Something went wrong")).toHaveCount(0);
    await shows[c.name]?.(page, id);
    expect(errors.filter((e) => !ignorableConsole.test(e))).toEqual([]);
  });
}

// N11 gap: the app opens a team's sections as /teams/:id?section=<name>; the website has a route for each.
const sections: Array<[string, string]> = [
  ["roster", "roster"],
  ["members", "roster"],
  ["events", "schedule"],
  ["chat", "chat"],
  ["stats", "stats"],
  ["playbook", "playbook"],
  ["videos", "videos"],
];
for (const [section, route] of sections) {
  test(`team section ?section=${section} opens /teams/{id}/${route}`, async ({ page }) => {
    test.setTimeout(90_000);
    const id = await ids();
    const { errors } = watchErrors(page);
    const res = await openMember(page, `/teams/${id.teamId}?section=${section}&utm=app`, "light", 3000);
    expect(res?.status(), "status").toBeLessThan(500);
    const got = new URL(page.url());
    expect(got.pathname).toBe(`/teams/${id.teamId}/${route}`);
    expect(got.searchParams.get("utm"), "other params stay").toBe("app");
    await expect(page.getByText("Something went wrong")).toHaveCount(0);
    expect(errors.filter((e) => !ignorableConsole.test(e))).toEqual([]);
  });
}

test("an unknown ?section= stays on the team home", async ({ page }) => {
  test.setTimeout(90_000);
  const id = await ids();
  await openMember(page, `/teams/${id.teamId}?section=nonsense`, "light", 3000);
  expect(new URL(page.url()).pathname).toBe(`/teams/${id.teamId}`);
  await expect(page.getByRole("heading", { level: 1, name: "Seattle Sidewinders" })).toBeVisible();
});
