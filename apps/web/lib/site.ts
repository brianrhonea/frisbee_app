// Site-wide constants. Store URLs are placeholders, as in
// apps/mobile/lib/config/store_links.dart; keep the two in step.

export const storeLinks = {
  appStore: "https://apps.apple.com/",
  playStore: "https://play.google.com/store/apps",
  /** False until the URLs point at the real listings; buttons say "Coming soon". */
  live: false,
} as const;

/** The app's own URL scheme (InviteLinks.scheme in the app). */
export const appScheme = "stall10";

export const siteName = "Stall 10";

export const divisionLabels: Record<string, string> = {
  mixed: "Mixed",
  open: "Open",
  women: "Women",
  masters: "Masters",
};

export const levelLabels: Record<string, string> = {
  club: "Club",
  college: "College",
  youth: "Youth",
  league: "League",
  pickup: "Pickup",
};

export const kindLabels: Record<string, string> = {
  team: "Team",
  community: "Community group",
  organization: "School or club",
};

/** "Open · Club · Austin" for a team or group. */
export function listingSubtitle(t: { kind?: string; division?: string; level?: string; city?: string }): string {
  const parts =
    t.kind && t.kind !== "team"
      ? [kindLabels[t.kind], t.city]
      : [divisionLabels[t.division ?? ""], levelLabels[t.level ?? ""], t.city];
  return parts.filter(Boolean).join(" · ");
}
