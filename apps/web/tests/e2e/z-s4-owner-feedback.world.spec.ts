import { expect, test, type Browser, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import { axeViolations, describeViolations, openMember } from "./helpers";

// Sprint 4, owner feedback (lane C, signed in, synthetic world): the Month list, the roster's Roles tab and
// Add member with the link picker, Join in Teams search, no claiming a roster spot, the overlap warning, the
// header's Message dialog and the phone header. Ada owns "Seattle Sidewinders" (Cam is an admin through a role, Ben a handler);
// Cam owns the "Cascade ..." teams and groups, which Ada is not on.
type World = { teamId: string; password: string; users: Record<"ada" | "ben" | "cam", { email: string; uid: string }> };
const world = () => JSON.parse(readFileSync("review/web/.auth/world.json", "utf8")) as World;
test.setTimeout(180_000);

/** A second browser context signed in as [who] (Ada's is the project's own). Pages it opens are the caller's to close. */
async function asUser(browser: Browser, baseURL: string, who: "ben" | "cam", viewport: { width: number; height: number }) {
  const w = world();
  const ctx = await browser.newContext({ baseURL, viewport, storageState: { cookies: [], origins: [] } });
  const page = await ctx.newPage();
  await page.goto("/sign-in", { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(5000); // the dev server hydrates late
  await page.getByLabel("Email or username").fill(w.users[who].email);
  await page.getByLabel("Password", { exact: true }).fill(w.password);
  await page.getByRole("button", { name: /^Log in$|^Sign in$/ }).click();
  await expect(page).not.toHaveURL(/sign-in/, { timeout: 60_000 });
  return { ctx, page };
}

const dayLabel = (d: Date) => d.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });

test("C1 Month: the whole month is a scrollable list by day, and a day in the grid scrolls it there", async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem("stall10.schedule.view", "month"));
  await openMember(page, "/schedule");
  const list = page.getByRole("region", { name: "Events this month" });
  // Events are seeded at +1, +2 (weekly), +4 days: the ones in this month are listed, each under its day.
  const today = new Date();
  const dayAt = (n: number) => new Date(today.getFullYear(), today.getMonth(), today.getDate() + n);
  const inMonth = (n: number) => dayAt(n).getMonth() === today.getMonth();
  const offsets = [1, 2, 4, 9, 16, 23, 30].filter(inMonth);
  if (offsets.length === 0) test.skip(true, "no seeded event falls in this month");
  await expect(list).toBeVisible();
  expect(await list.evaluate((el) => getComputedStyle(el).overflowY)).toBe("auto");
  await expect(list.locator(".sched-day")).toHaveCount(offsets.length);
  await expect(page.getByRole("heading", { level: 3 }).filter({ hasText: dayAt(offsets[0]!).toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" }) })).toBeVisible();
  // A day with no events: the list goes to the next day that has some, and highlights it.
  const empty = [3, 5, 6, 7, 8, 10].find((n) => inMonth(n) && offsets.some((o) => o > n));
  if (empty !== undefined) {
    const next = offsets.find((o) => o > empty)!;
    await page.getByRole("gridcell", { name: dayLabel(dayAt(empty)) }).click();
    const picked = list.locator(".sched-day.picked");
    await expect(picked).toHaveCount(1);
    await expect(picked.getByRole("heading")).toHaveText(dayAt(next).toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" }));
  }
  // The page itself does not scroll to it.
  const before = await page.evaluate(() => window.scrollY);
  await page.getByRole("gridcell", { name: dayLabel(dayAt(offsets[0]!)) }).click();
  await expect(list.locator(".sched-day.picked .ui-event", { hasText: "Tuesday practice" })).toBeVisible();
  expect(Math.abs((await page.evaluate(() => window.scrollY)) - before)).toBeLessThan(2);
  // Week and List are unchanged.
  await page.getByRole("tab", { name: "Week" }).click();
  await expect(page.getByRole("gridcell")).toHaveCount(7);
  await page.getByRole("tab", { name: "List" }).click();
  await expect(page.locator(".sched-item .ui-event").first()).toBeVisible();
});

test("C2 Roster: a Roles tab, Add member with a link picker, and axe", async ({ page, baseURL }) => {
  const w = world();
  await openMember(page, `/teams/${w.teamId}/roster`);
  const main = page.getByRole("main");
  // Roles tab: each tier and custom role with who holds it.
  await main.getByRole("tab", { name: "Roles" }).click();
  const roles = main.getByRole("region", { name: "Roles" });
  await expect(roles.locator("li", { has: page.getByRole("heading", { level: 3, name: /^Owner/ }) }).first()).toContainText("Ada Rivers");
  await expect(roles.locator("li", { has: page.getByRole("heading", { level: 3, name: /^Coordinators/ }) }).first()).toContainText("Cam Lindqvist");
  // Coach is listed because Cam holds it; Captain is not, as nobody does.
  await expect(roles.locator("li", { has: page.getByRole("heading", { level: 3, name: /^Coach/ }) }).first()).toContainText("Cam Lindqvist");
  await expect(roles.getByRole("heading", { level: 3, name: /^Captain/ })).toHaveCount(0);
  await expect(roles.locator("li", { has: page.getByRole("heading", { level: 3, name: /^Handlers/ }) }).first()).toContainText("Ben Okafor");
  await page.mouse.move(0, 0); // a hovered tab is not what is measured
  expect(describeViolations(await axeViolations(page)), "roles tab").toEqual([]);
  await expect(roles.getByRole("link", { name: "Edit roles" })).toHaveAttribute("href", `/teams/${w.teamId}/settings#team-roles`);
  await main.getByRole("tab", { name: "Roster" }).click();

  // Add member: Invite people, or Add player to roster.
  await main.getByRole("button", { name: "Add member" }).click();
  await expect(page.getByRole("menuitem", { name: "Invite people" })).toBeVisible();
  expect(describeViolations(await axeViolations(page)), "add member menu").toEqual([]);
  await page.getByRole("menuitem", { name: "Invite people" }).click();
  await expect(page.getByRole("dialog", { name: /Invite to Seattle Sidewinders/ })).toBeVisible();
  await page.keyboard.press("Escape");
  await main.getByRole("button", { name: "Add member" }).click();
  await page.getByRole("menuitem", { name: "Add player to roster" }).click();
  const dialog = page.getByRole("dialog", { name: "Add player to roster" });
  const picker = dialog.getByLabel(/Link to a member/);
  // Ada already has a spot, so she is not offered. The phone run links Cam, the desktop run Ben (each is
  // then taken, so the other run starts without them).
  const who = page.viewportSize()!.width < 600 ? "Cam Lindqvist" : "Ben Okafor";
  const options = await picker.locator("option").allTextContents();
  expect(options).toEqual(who === "Cam Lindqvist" ? ["Not linked (no account)", "Cam Lindqvist", "Ben Okafor"] : ["Not linked (no account)", "Ben Okafor"]);
  expect(describeViolations(await axeViolations(page)), "link picker").toEqual([]);
  await picker.selectOption({ label: who });
  await expect(dialog.getByLabel("Name", { exact: true })).toHaveValue(who);
  await dialog.getByRole("button", { name: "Save" }).click();
  await expect(dialog).toBeHidden();
  // The new spot is linked to Cam's profile.
  await expect(main.locator("table.roster-table a.person", { hasText: who })).toHaveAttribute("href", `/players/${who === "Cam Lindqvist" ? w.users.cam.uid : w.users.ben.uid}`, { timeout: 15_000 });
  void baseURL;
});

test("C2 Roster: a player sees no Add member", async ({ browser, baseURL }) => {
  const w = world();
  const { ctx, page } = await asUser(browser, baseURL!, "ben", { width: 1440, height: 900 });
  await openMember(page, `/teams/${w.teamId}/roster`);
  await expect(page.getByRole("main").getByRole("tab", { name: "Roles" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Add member" })).toHaveCount(0);
  await page.getByRole("main").getByRole("tab", { name: "Roles" }).click();
  await expect(page.getByRole("link", { name: "Edit roles" })).toHaveCount(0);
  await ctx.close();
});

test("C3 Teams search: Join only where a join path exists", async ({ page, browser, baseURL }) => {
  // One open and one approval group per width, so the other width's run has not already joined them.
  const x = page.viewportSize()!.width < 600 ? "A" : "B";
  const open = `Cascade Open Group ${x}`;
  const approval = `Cascade Approval Group ${x}`;
  // The join calls are answered here, so the shared world (and the other tests' counts) stay as they were.
  const joins: string[] = [];
  await page.route("**/v1/teams/*/{members,join-requests}", async (route) => {
    if (route.request().method() !== "POST") return route.fallback();
    joins.push(new URL(route.request().url()).pathname.split("/").slice(-2).join("/"));
    await route.fulfill({ status: 204 });
  });
  await openMember(page, "/teams");
  await page.getByRole("searchbox", { name: "Search teams and communities by name" }).fill("cascade");
  const rows = page.locator(".team-finder-list .ui-row");
  await expect(rows).toHaveCount(6);
  await expect(rows.filter({ hasText: "Cascade Request Team" }).getByRole("button", { name: /Ask to join/ })).toBeVisible();
  await expect(rows.filter({ hasText: approval }).getByRole("button", { name: /Ask to join/ })).toBeVisible();
  await expect(rows.filter({ hasText: open }).getByRole("button", { name: /^Join:/ })).toBeVisible();
  await expect(rows.filter({ hasText: "Cascade Plain Team" }).getByRole("button")).toHaveCount(0);
  expect(describeViolations(await axeViolations(page)), "teams search").toEqual([]);
  await rows.filter({ hasText: open }).getByRole("button", { name: /^Join:/ }).click();
  await expect(rows.filter({ hasText: open }).getByRole("status")).toHaveText("Joined");
  await expect(rows.filter({ hasText: open }).getByRole("button")).toHaveCount(0);
  await rows.filter({ hasText: approval }).getByRole("button", { name: /Ask to join/ }).click();
  await expect(rows.filter({ hasText: approval }).getByRole("status")).toHaveText("Requested");
  expect(joins.map((j) => j.split("/")[1])).toEqual(["members", "join-requests"]);
  // Signed out: no Join buttons.
  const ctx = await browser.newContext({ baseURL: baseURL!, storageState: { cookies: [], origins: [] } });
  const visitor = await ctx.newPage();
  await visitor.goto("/teams?q=cascade");
  await expect(visitor.locator(".team-finder-list .ui-row").first()).toBeVisible({ timeout: 30_000 });
  await expect(visitor.locator(".team-finder-list").getByRole("button")).toHaveCount(0);
  await ctx.close();
});

test("C4 Roster spots: a member cannot claim a spot, can still unlink themselves", async ({ page, browser, baseURL }) => {
  const w = world();
  // Ada's own spot (linked to her): Unlink me, and no claim button anywhere.
  await openMember(page, `/teams/${w.teamId}/stats/players`);
  await expect(page.getByRole("table")).toContainText("Sam Walk-on");
  await expect(page.getByRole("button", { name: "This is me" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Unlink me" })).toBeVisible();
  // Ben has no spot: the unlinked "Sam Walk-on" is not his to claim.
  const { ctx, page: ben } = await asUser(browser, baseURL!, "ben", { width: 1440, height: 900 });
  await openMember(ben, `/teams/${w.teamId}/stats/players`);
  await expect(ben.getByRole("table")).toContainText("Sam Walk-on");
  await expect(ben.getByRole("button", { name: "This is me" })).toHaveCount(0);
  await expect(ben.getByRole("button", { name: "Add player" })).toHaveCount(0);
  await ctx.close();
});

/** Opens the team's schedule with the new-event form, filled for tomorrow at [time] (local). */
async function fillNewEvent(page: Page, teamId: string, name: string, start: string, end: string) {
  const title = `${name} ${page.viewportSize()!.width}`;
  await openMember(page, `/teams/${teamId}/schedule?new=event`);
  const form = page.locator("form.event-editor");
  await form.getByLabel("Title").fill(title);
  const t = new Date();
  t.setDate(t.getDate() + 1);
  const day = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`;
  await form.getByLabel(/^Starts/).fill(`${day}T${start}`);
  await form.getByLabel(/^Ends/).fill(`${day}T${end}`);
  return { form, title };
}

test("C5 Overlap: saving on top of another event asks first, and Cancel saves nothing", async ({ page }) => {
  const w = world();
  // "Tuesday practice" is tomorrow 18:00 to 20:00.
  const { form, title } = await fillNewEvent(page, w.teamId, "Film session", "19:00", "20:30");
  await form.getByRole("button", { name: "Add", exact: true }).click();
  const confirm = page.getByRole("dialog", { name: "Overlapping event" });
  await expect(confirm).toContainText(/This overlaps with Tuesday practice \(.+\)\. Save anyway\?/);
  expect(describeViolations(await axeViolations(page)), "overlap confirm").toEqual([]);
  await confirm.getByRole("button", { name: "Cancel" }).click();
  await expect(confirm).toBeHidden();
  await expect(form.getByLabel("Title")).toHaveValue(title);
  await expect(page.locator(".event-row, .ui-event", { hasText: title })).toHaveCount(0);
  // Not overlapping: no question, it saves.
  // Another hour for each width, so one width's saved event is not the other's overlap.
  const [h1, h2] = page.viewportSize()!.width < 600 ? ["07", "08"] : ["09", "10"];
  await form.getByLabel(/^Starts/).fill((await form.getByLabel(/^Starts/).inputValue()).replace("T19:00", `T${h1}:00`));
  await form.getByLabel(/^Ends/).fill((await form.getByLabel(/^Ends/).inputValue()).replace("T20:30", `T${h2}:00`));
  await form.getByRole("button", { name: "Add", exact: true }).click();
  await expect(page.getByRole("dialog", { name: "Overlapping event" })).toHaveCount(0);
  await expect(page.locator("form.event-editor")).toBeHidden({ timeout: 15_000 });
});

test("C5 Overlap: Save anyway saves the overlapping event", async ({ page }) => {
  const w = world();
  const { form, title } = await fillNewEvent(page, w.teamId, "Overlap on purpose", "18:30", "19:30");
  await form.getByRole("button", { name: "Add", exact: true }).click();
  await page.getByRole("dialog", { name: "Overlapping event" }).getByRole("button", { name: "Save anyway" }).click();
  await expect(page.locator("form.event-editor")).toBeHidden({ timeout: 15_000 });
  await expect(page.getByText(title).first()).toBeVisible();
});

test("C5 Overlap: the personal editor asks too", async ({ page }) => {
  await openMember(page, "/schedule");
  await page.getByRole("button", { name: "Add event" }).click();
  const form = page.locator("form").filter({ has: page.getByLabel("Title") }).first();
  await form.getByLabel("Title").fill("Run");
  const t = new Date();
  t.setDate(t.getDate() + 1);
  const day = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`;
  await form.getByLabel(/^Starts/).fill(`${day}T18:30`);
  await form.getByRole("button", { name: /^Add$|^Save$/ }).click();
  const confirm = page.getByRole("dialog", { name: "Overlapping event" });
  await expect(confirm).toContainText("This overlaps with Tuesday practice");
  await confirm.getByRole("button", { name: "Cancel" }).click();
  await expect(confirm).toBeHidden();
});

test("C6 Header Message: Team chat and the staff for a member; staff only for an outsider; none for a visitor", async ({ page, browser, baseURL }) => {
  const w = world();
  await openMember(page, `/teams/${w.teamId}`);
  const head = page.locator(".team-head");
  await head.getByRole("button", { name: "Message" }).click();
  const dialog = page.getByRole("dialog", { name: "Message the team" });
  await expect(dialog.getByRole("link", { name: "Team chat" })).toHaveAttribute("href", `/teams/${w.teamId}/chat`);
  await expect(dialog.getByRole("button", { name: "Message Cam Lindqvist" })).toBeVisible();
  await expect(dialog.getByText("Coach", { exact: true })).toBeVisible();
  // Not the viewer, not a plain player.
  await expect(dialog.getByRole("button", { name: "Message Ada Rivers" })).toHaveCount(0);
  await expect(dialog.getByRole("button", { name: "Message Ben Okafor" })).toHaveCount(0);
  expect(describeViolations(await axeViolations(page)), "message dialog").toEqual([]);
  await dialog.getByRole("button", { name: "Message Cam Lindqvist" }).click();
  await expect(page).toHaveURL(/\/messages\?c=/, { timeout: 20_000 });

  // A signed-in outsider (Ada on Cam's team): the staff only, no Team chat.
  await openMember(page, "/teams");
  await page.getByRole("searchbox", { name: "Search teams and communities by name" }).fill("cascade request");
  await page.locator(".team-finder-list .ui-row a.ui-row-main", { hasText: "Cascade Request Team" }).click();
  await expect(page.locator(".team-head").getByRole("heading", { level: 1 })).toHaveText("Cascade Request Team", { timeout: 20_000 });
  const teamUrl = page.url();
  await page.locator(".team-head").getByRole("button", { name: "Message" }).click();
  const out = page.getByRole("dialog", { name: "Message the team" });
  await expect(out.getByRole("button", { name: "Message Cam Lindqvist" })).toBeVisible();
  await expect(out.getByRole("link", { name: "Team chat" })).toHaveCount(0);
  await page.keyboard.press("Escape");

  // A visitor: no Message.
  const ctx = await browser.newContext({ baseURL: baseURL!, storageState: { cookies: [], origins: [] } });
  const visitor = await ctx.newPage();
  await visitor.goto(teamUrl);
  await expect(visitor.locator(".team-head").getByRole("heading", { level: 1 })).toBeVisible({ timeout: 30_000 });
  await expect(visitor.locator(".team-head").getByRole("button", { name: "Message" })).toHaveCount(0);
  await ctx.close();
});

test("Team header: the Settings gear is on screen, and the header stays compact", async ({ page }) => {
  const w = world();
  await openMember(page, `/teams/${w.teamId}`);
  const vp = page.viewportSize()!;
  const gear = page.locator(".team-head").getByRole("link", { name: "Settings" });
  await expect(gear).toBeVisible();
  const box = (await gear.boundingBox())!;
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(vp.width);
  // Nothing in the header's actions overlaps another, and the gear is what is on top at its own centre.
  const actions = await page.locator(".team-head .ui-cover-actions > *").evaluateAll((els) =>
    els.map((el) => {
      const r = el.getBoundingClientRect();
      return { label: el.getAttribute("aria-label") || el.textContent?.trim() || el.tagName, x: r.x, y: r.y, w: r.width, h: r.height };
    }),
  );
  const others = actions.filter((a) => a.label !== "Settings" && a.w > 0 && a.h > 0);
  const g = actions.find((a) => a.label === "Settings")!;
  for (const o of others) {
    const apart = o.x + o.w <= g.x + 0.5 || g.x + g.w <= o.x + 0.5 || o.y + o.h <= g.y + 0.5 || g.y + g.h <= o.y + 0.5;
    expect(apart, `the gear ${JSON.stringify(g)} overlaps ${JSON.stringify(o)}`).toBe(true);
  }
  for (let i = 0; i < others.length; i++) {
    for (let j = i + 1; j < others.length; j++) {
      const a = others[i]!;
      const b = others[j]!;
      expect(a.x + a.w <= b.x + 0.5 || b.x + b.w <= a.x + 0.5 || a.y + a.h <= b.y + 0.5 || b.y + b.h <= a.y + 0.5, `${a.label} overlaps ${b.label}`).toBe(true);
    }
  }
  const onTop = await gear.evaluate((el) => {
    const r = el.getBoundingClientRect();
    const hit = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
    return hit === el || el.contains(hit);
  });
  expect(onTop, "the gear is not covered").toBe(true);
  // The page does not scroll sideways because of it.
  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0);
});

test("Phone Home: nothing shifts the layout or scrolls the page after load", async ({ page }) => {
  const vp = page.viewportSize()!;
  test.skip(vp.width > 600, "the phone measurement");
  // Layout shifts, with what moved, and the scroll position over time.
  await page.addInitScript(() => {
    const w = window as unknown as { __shifts: string[]; __scroll: Array<[number, number, number]> };
    w.__shifts = [];
    w.__scroll = [];
    new PerformanceObserver((list) => {
      for (const e of list.getEntries() as unknown as Array<{ value: number; hadRecentInput: boolean; sources?: Array<{ node?: Element; previousRect: DOMRect; currentRect: DOMRect }> }>) {
        if (e.hadRecentInput) continue;
        const src = (e.sources ?? []).map((x) => `${x.node?.nodeName?.toLowerCase()}.${String((x.node as HTMLElement | undefined)?.className ?? "").slice(0, 30)} y ${Math.round(x.previousRect.y)}->${Math.round(x.currentRect.y)} h ${Math.round(x.previousRect.height)}->${Math.round(x.currentRect.height)}`);
        w.__shifts.push(`${e.value.toFixed(4)} ${src.join(" | ")}`);
      }
    }).observe({ type: "layout-shift", buffered: true });
    const t0 = performance.now();
    const tick = () => {
      w.__scroll.push([Math.round(performance.now() - t0), Math.round(window.scrollY), document.documentElement.scrollHeight]);
      if (performance.now() - t0 < 9000) setTimeout(tick, 250);
    };
    tick();
  });
  await openMember(page, "/", "light", 9500);
  const r = await page.evaluate(() => {
    const w = window as unknown as { __shifts: string[]; __scroll: Array<[number, number, number]> };
    return { shifts: w.__shifts, scroll: w.__scroll.filter((_, i) => i % 4 === 0), y: window.scrollY };
  });
  console.log("home 375", JSON.stringify(r));
  // The footer arriving below the fold while the page loads is not what is on screen: leave it out.
  const total = r.shifts.filter((x) => !x.includes("footer.site-footer")).reduce((n, x) => n + Number.parseFloat(x), 0);
  expect(total, `layout shifts: ${r.shifts.join(" ; ")}`).toBeLessThan(0.05);
  expect(r.y, "the page has scrolled by itself").toBe(0);
});

test("D1 New events send a client id, a team's and a personal one", async ({ page }) => {
  const w = world();
  const idRule = /^[A-Za-z0-9]{1,40}$/;
  const wide = page.viewportSize()!.width >= 600;
  const t = new Date();
  t.setDate(t.getDate() + 5); // a day with nothing else on it (the Week test counts the picked day's events)
  const day = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`;
  // A team event (an hour no other test uses; one per width).
  const hour = wide ? "04" : "03";
  await openMember(page, `/teams/${w.teamId}/schedule?new=event`);
  const form = page.locator("form.event-editor");
  await form.getByLabel("Title").fill(`Early swim ${page.viewportSize()!.width}`);
  await form.getByLabel(/^Starts/).fill(`${day}T${hour}:00`);
  await form.getByLabel(/^Ends/).fill(`${day}T${hour}:30`);
  const teamPost = page.waitForRequest((r) => r.method() === "POST" && /\/v1\/teams\/[^/]+\/events$/.test(r.url()));
  await form.getByRole("button", { name: "Add", exact: true }).click();
  const teamBody = (await teamPost).postDataJSON() as { id?: string };
  expect(teamBody.id).toMatch(idRule);
  await expect(page.locator("form.event-editor")).toBeHidden({ timeout: 15_000 });
  // A personal event.
  await openMember(page, "/schedule");
  await page.getByRole("button", { name: "Add event" }).click();
  const mine = page.locator("form").filter({ has: page.getByLabel("Title") }).first();
  await mine.getByLabel("Title").fill(`Early run ${page.viewportSize()!.width}`);
  await mine.getByLabel(/^Starts/).fill(`${day}T${wide ? "05" : "02"}:00`);
  const calPost = page.waitForRequest((r) => r.method() === "POST" && /\/v1\/calendars\/[^/]+\/events$/.test(r.url()));
  await mine.getByRole("button", { name: /^Add$/ }).click();
  const calBody = (await calPost).postDataJSON() as { id?: string };
  expect(calBody.id).toMatch(idRule);
  expect(calBody.id).not.toBe(teamBody.id);
});

test("C5 Overlap: a later occurrence of a repeating event is checked too", async ({ page }) => {
  const w = world();
  await openMember(page, `/teams/${w.teamId}/schedule?new=event`);
  const form = page.locator("form.event-editor");
  await form.getByLabel("Title").fill("Daily film");
  const t = new Date();
  t.setDate(t.getDate() + 1);
  const day = `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`;
  // Tomorrow at 10:30 is free; four days on, "Scrimmage vs Rainiers" (10:00 to 12:00) is not.
  await form.getByLabel(/^Starts/).fill(`${day}T10:30`);
  await form.getByLabel(/^Ends/).fill(`${day}T11:30`);
  await form.getByLabel("Repeat").selectOption("daily");
  await form.getByRole("button", { name: "Add", exact: true }).click();
  const confirm = page.getByRole("dialog", { name: "Overlapping event" });
  await expect(confirm).toContainText("This overlaps with Scrimmage vs Rainiers");
  await confirm.getByRole("button", { name: "Cancel" }).click();
  await expect(confirm).toBeHidden();
});

test("S4 Profile: your own roster spots, with Unlink after a confirmation; not on anyone else's page", async ({ page, browser, baseURL }) => {
  const w = world();
  await openMember(page, `/players/${w.users.ada.uid}`);
  const card = page.getByRole("region", { name: "Roster spots" });
  await expect(card).toBeVisible({ timeout: 30_000 });
  await expect(card).toContainText("Seattle Sidewinders");
  await expect(card).toContainText("Ada Rivers · #1");
  expect(describeViolations(await axeViolations(page)), "roster spots card").toEqual([]);
  await card.getByRole("button", { name: "Unlink from Seattle Sidewinders" }).click();
  const confirm = page.getByRole("dialog", { name: /Unlink from Seattle Sidewinders/ });
  await expect(confirm).toContainText("stop counting on your profile");
  await confirm.getByRole("button", { name: "Cancel" }).click();
  await expect(confirm).toBeHidden();
  await expect(card).toBeVisible();
  // Ben looking at Ada's page: no card.
  const { ctx, page: ben } = await asUser(browser, baseURL!, "ben", { width: 1440, height: 900 });
  await openMember(ben, `/players/${w.users.ada.uid}`);
  await expect(ben.getByRole("heading", { level: 1 }).first()).toBeVisible({ timeout: 30_000 });
  await expect(ben.getByRole("region", { name: "Roster spots" })).toHaveCount(0);
  await ctx.close();
});
