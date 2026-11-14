// Responses of the API's public routes (`GET /v1/public/...`): what anyone,
// signed in or not, may see. Built by apps/api/src/browse from the same
// allow-lists as the `browse` Cloud Functions. Dates are ISO 8601 strings.

/** A stored photo with a URL that Storage's rules let anyone read. */
export interface PublicImage {
  path: string;
  name?: string;
  contentType?: string;
  size?: number;
  url: string;
}

export interface PublicWorkout {
  activity?: string;
  durationMinutes?: number;
  durationSeconds?: number;
  distanceKm?: number;
  effort?: number;
  exercises?: Array<{ name: string; sets?: number; reps?: number; weight?: string }>;
}

export interface PublicPostEvent {
  eventId?: string;
  title?: string;
  type?: string;
  startsAt?: string;
  endsAt?: string;
  location?: string;
  teamId?: string;
  teamName?: string;
}

/** A player's post (`posts/{id}`), without who liked or reposted it. */
export interface PublicPost {
  id: string;
  authorId?: string;
  authorName?: string;
  authorPhotoUrl?: string;
  body?: string;
  links?: string[];
  images?: PublicImage[];
  workout?: PublicWorkout;
  event?: PublicPostEvent;
  repostOf?: { postId: string; authorId: string; authorName?: string };
  /**
   * For a repost: the post it shares, as it is now (null once it's deleted
   * or hidden). Likes and reposts of a repost count toward this original.
   */
  original?: PublicPost | null;
  tournamentKey?: string;
  tournamentName?: string;
  commentCount?: number;
  likeCount: number;
  repostCount: number;
  createdAt?: string;
  updatedAt?: string;
}

/** A page of posts; pass `next` back as `before` for the page after. */
export interface PostPage {
  posts: PublicPost[];
  /** Cursor (ms since epoch) for the next page, or null at the end. */
  next: number | null;
}

/** A player's profile; a private one is only its card. */
export interface PublicProfile {
  id: string;
  name?: string;
  username?: string;
  photoUrl?: string;
  private?: boolean;
  bio?: string;
  pronouns?: string;
  hometown?: string;
  school?: string;
  throwingHand?: string;
  playingSince?: number;
  visibility?: { stats: boolean; teams: boolean; games: boolean };
  teams?: ProfileTeam[];
  /** Season (the year, e.g. "2026") → totals. */
  stats?: Record<string, StatTotals>;
  /** Newest first, at most 5. */
  games?: ProfileGame[];
}

/** A team on a player's profile (ProfileTeam in the app). */
export interface ProfileTeam {
  id: string;
  name: string;
  kind?: "team" | "community" | "organization";
  subtitle?: string;
  role?: string;
  number?: number;
  position?: string;
}

export interface StatTotals {
  games?: number;
  points?: number;
  goals?: number;
  assists?: number;
  blocks?: number;
  completions?: number;
  throwaways?: number;
  catches?: number;
  drops?: number;
}

export interface ProfileGame {
  date?: string;
  teamName?: string;
  opponent?: string;
  ourScore?: number;
  theirScore?: number;
  line?: string;
}

export interface ProfilePage extends PostPage {
  profile: PublicProfile;
}

/**
 * A player's profile as a signed-in member sees it (`GET /v1/players/:uid`):
 * a private one in full for the player and the people they let follow
 * them, else [locked] with only its card.
 */
export interface MemberProfilePage extends ProfilePage {
  locked: boolean;
}

/** A team, group or school/club's directory listing. */
export interface PublicListing {
  id: string;
  name?: string;
  division?: string;
  level?: string;
  city?: string;
  kind?: "team" | "community" | "organization";
  description?: string;
  requiresApproval?: boolean;
  location?: { address: string; lat: number; lng: number } | null;
}

export interface PublicTeamPost {
  id: string;
  title?: string;
  body?: string;
  location?: string;
  links?: string[];
  images?: PublicImage[];
  authorId?: string;
  authorName?: string;
  tournamentKey?: string;
  createdAt?: string;
  updatedAt?: string;
}

export interface PublicEvent {
  id: string;
  title?: string;
  type?: string;
  startsAt?: string;
  endsAt?: string;
  location?: string;
  notes?: string;
}

export interface TeamPage {
  team: PublicListing;
  /** Empty for a private group: only members see its posts and events. */
  posts: PublicTeamPost[];
  events: PublicEvent[];
}

export interface PublicTournament {
  id: string;
  groupId?: string;
  tournamentId?: string;
  name?: string;
  startsAt?: string;
  endsOn?: string;
  status?: string;
  format?: string;
}

export interface EventsPage {
  events: Array<PublicEvent & { teamId: string; teamName: string }>;
  tournaments: PublicTournament[];
}

export type SearchKind = "players" | "teams";

export interface SearchPage {
  players: PublicProfile[];
  teams: PublicListing[];
}
