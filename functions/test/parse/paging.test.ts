import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { parseRankingsPage } from "../../src/usau/parse";
import { fetchAllRankings } from "../../src/usau/sync";

const fixture = (name: string) =>
  readFileSync(join(__dirname, "..", "fixtures", name), "utf8");

const URL_ = "https://play.usaultimate.org/teams/events/team_rankings/?RankSet=Club-Mixed";

describe("parseRankingsPage (paged synthetic fixtures)", () => {
  it("skips the pager row and finds the Next postback", () => {
    const page = parseRankingsPage(fixture("rankings_paged_1.html"));
    expect(page.entries.map((e) => e.teamName)).toEqual(["Alpha", "Beta", "Gamma"]);
    expect(page.next).toEqual({
      action: "./?RankSet=Club-Mixed",
      fields: {
        __EVENTTARGET: "CT_Main_0$gvList$ctl12$ctl00$ctl05",
        __EVENTARGUMENT: "",
        __VIEWSTATE: "vs-page-1",
        __EVENTVALIDATION: "ev-page-1",
        CT_Main_0$F_RankSet: "12",
      },
    });
  });

  it("has no next postback on the last page", () => {
    const page = parseRankingsPage(fixture("rankings_paged_3.html"));
    expect(page.entries.map((e) => e.teamName)).toEqual(["Eta"]);
    expect(page.next).toBeNull();
  });
});

describe("fetchAllRankings", () => {
  it("follows Next postbacks across every page", async () => {
    const targets: string[] = [];
    const fetchFn = (async (url: string, init: RequestInit) => {
      expect(url).toBe(URL_);
      if (init.method === "GET") {
        return new Response(fixture("rankings_paged_1.html"), {
          headers: { "Set-Cookie": "ASP.NET_SessionId=abc; path=/; HttpOnly" },
        });
      }
      expect((init.headers as Record<string, string>).Cookie).toBe("ASP.NET_SessionId=abc");
      const form = init.body as URLSearchParams;
      targets.push(form.get("__EVENTTARGET")!);
      const next = { "vs-page-1": 2, "vs-page-2": 3 }[form.get("__VIEWSTATE")!];
      return next
        ? new Response(fixture(`rankings_paged_${next}.html`))
        : new Response("", { status: 500 });
    }) as unknown as typeof fetch;

    const entries = await fetchAllRankings(URL_, { fetchFn, delayMs: 0 });
    expect(entries.map((e) => e.rank)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(entries.at(-1)?.teamName).toBe("Eta");
    expect(targets).toEqual([
      "CT_Main_0$gvList$ctl12$ctl00$ctl05",
      "CT_Main_0$gvList$ctl12$ctl00$ctl06",
    ]);
  });
});
