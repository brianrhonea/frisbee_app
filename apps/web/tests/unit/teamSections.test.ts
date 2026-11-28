import { describe, expect, it } from "vitest";
import { teamSectionRedirects, teamSectionRoutes } from "@/lib/teamSections";

describe("/teams/:id?section= redirects (S5 FX1, N11 gap)", () => {
  it("maps each section the app links to onto the website's route for it", () => {
    for (const s of ["roster", "events", "chat", "stats", "members", "playbook", "videos"]) expect(teamSectionRoutes[s], s).toBeTruthy();
    expect(teamSectionRoutes.events).toBe("schedule");
    expect(teamSectionRoutes.members).toBe("roster");
  });

  it("redirects only a known section, from the team home, to the same team's route", () => {
    for (const r of teamSectionRedirects) {
      expect(r.source).toBe("/teams/:teamId");
      expect(r.has).toHaveLength(1);
      expect(r.has[0]).toMatchObject({ type: "query", key: "section" });
      expect(r.destination).toMatch(/^\/teams\/:teamId\/[a-z]+$/);
      expect(r.permanent).toBe(false);
    }
    // An unknown section matches no rule, so the team home shows.
    expect(teamSectionRedirects.some((r) => r.has[0]!.value === "nonsense")).toBe(false);
  });
});
