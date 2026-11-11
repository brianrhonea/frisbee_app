// The signed-in member's own dashboard (`GET /v1/me/home`): what the app's
// home screen shows. Built by apps/api/src/me with the caller from the ID
// token; never cached publicly.
import type { PostPage, PublicProfile } from "./browse.js";

/** A team or group the caller belongs to. */
export interface MyTeam {
  id: string;
  name: string;
  kind: "team" | "community" | "organization";
  /** owner, coach, captain, player or stats. */
  role: string;
  division?: string;
  level?: string;
  city?: string;
}

/** An upcoming event on one of the caller's teams that they may see. */
export interface MyEvent {
  id: string;
  teamId: string;
  teamName: string;
  title?: string;
  type?: string;
  startsAt?: string;
  endsAt?: string;
  location?: string;
  /** The caller's answer: going, maybe or notGoing. */
  rsvp?: string;
}

export interface MeHome {
  /** Their own profile, private details included. */
  profile: PublicProfile & {
    /** No username claimed yet (an account made on the web): ask for one. */
    needsUsername: boolean;
  };
  teams: MyTeam[];
  /** Next upcoming events across their teams, soonest first. */
  events: MyEvent[];
  /** Posts from people they follow, and their own; newest first. */
  feed: PostPage;
}
