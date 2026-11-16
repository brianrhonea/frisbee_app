// Notifications carry the app's route (firebase/functions notifications
// model). The website has most of the same pages under other paths; this
// maps each app route to the website page that shows the same thing, so a
// notification never links to a page the site doesn't have.

/** Where the website sends people for something only the app has. */
export const appOnlyRoute = "/get-the-app";

// A document id: letters, digits, _ - and inner dots only, so a stored
// route can't climb out with `..`, a backslash or an escape (`%2e`).
const id = "([A-Za-z0-9_-][A-Za-z0-9_.-]*)";
const enc = encodeURIComponent;
type Query = Map<string, string>;
type Rule = [RegExp, (m: RegExpMatchArray, q: Query) => string];

/** The app's team sections (TeamSection.path) and the website's page for each. */
const teamSections = new Map([
  ["events", "/schedule"],
  ["chat", "/chat"],
  ["roster", "/roster"],
  ["members", "/roster"],
  ["teams", "/teams"],
  ["playbook", "/playbook"],
  ["videos", "/videos"],
  ["stats", "/stats"],
  ["tournaments", "/tournaments"],
]);
const rules: Rule[] = [
  // Follow requests moved from Settings to Notifications; older notices keep the old route.
  [/^\/(settings|notifications)\/follow-requests$/, () => "/notifications/requests"],
  [/^\/settings\/calendar$/, () => "/settings/calendar"],
  [new RegExp(`^/posts/${id}$`), (m) => `/posts/${m[1]}`],
  [new RegExp(`^/players/${id}$`), (m) => `/players/${m[1]}`],
  // The website opens a conversation beside the inbox (?c=).
  [/^\/messages\/(new|new-group)$/, () => "/messages"],
  [new RegExp(`^/messages/${id}$`), (m) => `/messages?c=${enc(m[1]!)}`],
  [/^\/messages$/, () => "/messages"],
  [new RegExp(`^/my-events/${id}$`), () => "/schedule"],
  [new RegExp(`^/team-events/${id}/${id}$`), (m) => `/teams/${m[1]}/schedule?event=${enc(m[2]!)}`],
  [new RegExp(`^/team-meetings/${id}/${id}(/room|/edit)?$`), (m) => `/teams/${m[1]}/meetings/${enc(m[2]!)}${m[3] ?? ""}`],
  [/^\/teams$/, () => "/teams"],
  // A section of the team's page (?section=, Routes.teamSection in the
  // app) is a page of its own on the website; unknown sections open the feed.
  [new RegExp(`^/teams/${id}$`), (m, q) => `/teams/${m[1]}${teamSections.get(q.get("section") ?? "") ?? ""}`],
  [new RegExp(`^/teams/${id}/chats/${id}$`), (m) => `/teams/${m[1]}/chat?room=${enc(m[2]!)}`],
  [new RegExp(`^/teams/${id}/events$`), (m) => `/teams/${m[1]}/schedule`],
  [new RegExp(`^/teams/${id}/members$`), (m) => `/teams/${m[1]}/roster`],
  [new RegExp(`^/teams/${id}/plays/${id}$`), (m) => `/teams/${m[1]}/plays/${m[2]}`],
  [new RegExp(`^/teams/${id}/stats/games/${id}$`), (m) => `/teams/${m[1]}/stats/games/${m[2]}`],
  [new RegExp(`^/teams/${id}/stats/tournaments/${id}$`), (m) => `/teams/${m[1]}/stats/tournaments/${m[2]}`],
  [new RegExp(`^/teams/${id}/stats/season$`), (m) => `/teams/${m[1]}/stats/season`],
  [new RegExp(`^/team-videos/${id}/${id}$`), (m) => `/teams/${m[1]}/videos/${m[2]}`],
  // Community group tournaments are pages of the group on the website.
  [new RegExp(`^/group-tournaments/${id}/${id}(/edit)?$`), (m) => `/teams/${m[1]}/tournaments/${m[2]}${m[3] ?? ""}`],
  [/^\/tournaments$/, () => "/tournaments"],
  [/^\/tournaments\/host$/, () => "/tournaments/host"],
  [/^\/tournaments\/new$/, (_, q) => `/tournaments/new${query(q, "host", "type")}`],
  // ?host= opens that group's tournament when no hosted one has the id.
  [new RegExp(`^/tournaments/${id}$`), (m, q) => `/tournaments/${m[1]}${query(q, "host")}`],
  [new RegExp(`^/tournaments/${id}/(edit|signups)$`), (m) => `/tournaments/${m[1]}/${m[2]}`],
  // The host's balanced draft, and the captains' live draft.
  [new RegExp(`^/tournaments/${id}/(draft|live-draft)/${id}$`), (m) => `/tournaments/${m[1]}/${m[2]}/${m[3]}`],
];

/** A query string's values (the first of each key), decoded. */
function parseQuery(search: string): Query {
  const q: Query = new Map();
  for (const pair of search.split("&")) {
    if (!pair) continue;
    const at = pair.indexOf("=");
    const [k, v] = at < 0 ? [pair, ""] : [pair.slice(0, at), pair.slice(at + 1)];
    try {
      const key = decodeURIComponent(k.replace(/\+/g, " "));
      if (!q.has(key)) q.set(key, decodeURIComponent(v.replace(/\+/g, " ")));
    } catch {
      // A malformed escape: skip that pair.
    }
  }
  return q;
}

/** `?k=v&…` with only [keys] of [q], or "" when none are set. */
function query(q: Query, ...keys: string[]): string {
  const parts = keys.filter((k) => q.get(k)).map((k) => `${enc(k)}=${enc(q.get(k)!)}`);
  return parts.length ? `?${parts.join("&")}` : "";
}

/**
 * The website page for an app route, or [appOnlyRoute] when the site has
 * nothing like it; null for something that isn't a route at all.
 */
export function webRoute(appRoute: string | null | undefined): string | null {
  if (!appRoute || !appRoute.startsWith("/") || appRoute.startsWith("//")) return null;
  const cut = appRoute.search(/[?#]/);
  const path = cut < 0 ? appRoute : appRoute.slice(0, cut);
  const q = parseQuery(cut < 0 || appRoute[cut] === "#" ? "" : appRoute.slice(cut + 1).split("#")[0]!);
  for (const [pattern, to] of rules) {
    const m = path.match(pattern);
    if (m) return to(m, q);
  }
  return appOnlyRoute;
}
