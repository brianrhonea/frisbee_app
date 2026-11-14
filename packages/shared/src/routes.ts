// Notifications carry the app's route (firebase/functions notifications
// model). The website has most of the same pages under other paths; this
// maps each app route to the website page that shows the same thing, so a
// notification never links to a page the site doesn't have.

/** Where the website sends people for something only the app has. */
export const appOnlyRoute = "/get-the-app";

const id = "([^/?#]+)";
const rules: Array<[RegExp, (m: RegExpMatchArray) => string]> = [
  [/^\/settings\/follow-requests$/, () => "/settings/requests"],
  [/^\/settings\/calendar$/, () => "/settings/calendar"],
  [new RegExp(`^/posts/${id}$`), (m) => `/posts/${m[1]}`],
  [new RegExp(`^/players/${id}$`), (m) => `/players/${m[1]}`],
  // Conversations are read in the app; the website lists them.
  [/^\/messages(\/[^/?#]+)?$/, () => "/messages"],
  [new RegExp(`^/my-events/${id}$`), () => "/schedule"],
  [new RegExp(`^/team-events/${id}/${id}$`), (m) => `/teams/${m[1]}/schedule`],
  [new RegExp(`^/team-meetings/${id}/${id}(/room)?$`), (m) => `/teams/${m[1]}`],
  [/^\/teams$/, () => "/teams"],
  [new RegExp(`^/teams/${id}$`), (m) => `/teams/${m[1]}`],
  [new RegExp(`^/teams/${id}/chats/${id}$`), (m) => `/teams/${m[1]}/chat`],
  [new RegExp(`^/teams/${id}/events$`), (m) => `/teams/${m[1]}/schedule`],
  [new RegExp(`^/teams/${id}/members$`), (m) => `/teams/${m[1]}/roster`],
  [new RegExp(`^/teams/${id}/plays/${id}$`), (m) => `/teams/${m[1]}`],
  [new RegExp(`^/tournaments/${id}(/.*)?$`), () => "/events"],
];

/**
 * The website page for an app route, or [appOnlyRoute] when the site has
 * nothing like it; null for something that isn't a route at all.
 */
export function webRoute(appRoute: string | null | undefined): string | null {
  if (!appRoute || !appRoute.startsWith("/")) return null;
  for (const [pattern, to] of rules) {
    const m = appRoute.match(pattern);
    if (m) return to(m);
  }
  return appOnlyRoute;
}
