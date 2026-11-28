/**
 * The app's team links open a section with `/teams/:id?section=<name>` (Routes.teamSection in the app,
 * packages/shared/fixtures/shared_links.json). The website's sections are routes, so each name maps to the
 * route that shows it; an unknown name stays on the team home. Members are listed on the roster page.
 */
export const teamSectionRoutes: Record<string, string> = {
  roster: "roster",
  members: "roster",
  events: "schedule",
  chat: "chat",
  stats: "stats",
  playbook: "playbook",
  videos: "videos",
  tournaments: "tournaments",
};

/** `next.config` redirects for them: only a known `section` matches; any other query params are kept. */
export const teamSectionRedirects = Object.entries(teamSectionRoutes).map(([section, route]) => ({
  source: "/teams/:teamId",
  has: [{ type: "query" as const, key: "section", value: section }],
  destination: `/teams/:teamId/${route}`,
  permanent: false,
}));
