// Read-only pages for signed-out visitors to the website, exported as the
// `browse` group:
//   firebase deploy --only functions:browse
//
// firestore.rules keep every read to signed-in users; these callables are
// the only way in without an account. Each answers with allow-listed fields
// only (model.ts), leaves out private profiles and private groups, and is
// rate limited per visitor so the directory can't be scraped in bulk.

import { type DocumentData, getFirestore, type Query, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall, type CallableRequest } from "firebase-functions/v2/https";

import { overLimit } from "../api/functions";
import { isMuted, searchKey, searchLimit } from "../api/model";
import { enforceAppCheck } from "../options";
import {
  clientIp,
  eventLimit,
  eventView,
  isPrivateGroup,
  isPrivateProfile,
  isPublicTeamPost,
  listingView,
  pageSize,
  parseBefore,
  postAuthors,
  postView,
  profileView,
  searchProfileView,
  teamPostView,
  validId,
  visitorKey,
} from "./model";

type Data = Record<string, unknown>;

/** Visitors have no account, so no App Check either on the website yet. */
const options = { enforceAppCheck, cors: true, maxInstances: 5 };

/** Firestore values as plain JSON; timestamps become `{__ts: millis}`. */
function plain(value: unknown): unknown {
  if (value instanceof Timestamp) return { __ts: value.toMillis() };
  if (Array.isArray(value)) return value.map(plain);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, plain(v)]));
  }
  return value;
}

/** Turns away a visitor (or signed-in user) past the browse limit. */
async function admit(req: CallableRequest): Promise<void> {
  const raw = req.rawRequest;
  const key = req.auth?.uid ?? visitorKey(clientIp(raw?.headers?.["x-forwarded-for"], raw?.ip));
  const limits = await getFirestore().doc(`limits/${key}`).get();
  const muted = limits.get("mutedUntil") as Timestamp | undefined;
  if (isMuted(muted?.toMillis(), Date.now()) || (await overLimit(key, "browse"))) {
    throw new HttpsError("resource-exhausted", "Too many requests. Try again in a few minutes.");
  }
}

const input = (req: CallableRequest): Data => (req.data && typeof req.data === "object" ? (req.data as Data) : {});

/** Profiles by id, for checking who's private. */
async function profiles(ids: Iterable<string>): Promise<Map<string, Data>> {
  const unique = [...new Set(ids)];
  if (unique.length === 0) return new Map();
  const db = getFirestore();
  const snaps = await db.getAll(...unique.map((id) => db.doc(`profiles/${id}`)));
  return new Map(snaps.filter((s) => s.exists).map((s) => [s.id, s.data() as Data]));
}

/** [docs] as public posts: those whose authors (and reposts' originals) aren't private. */
async function publicPosts(docs: { id: string; data: () => DocumentData }[]) {
  const people = await profiles(docs.flatMap((d) => postAuthors(d.data())));
  return docs
    .filter((d) => postAuthors(d.data()).every((id) => !isPrivateProfile(people.get(id))))
    .map((d) => ({ id: d.id, data: plain(postView(d.data())) }));
}

function page(query: Query, before: number | null): Query {
  const ordered = query.orderBy("createdAt", "desc");
  return (before ? ordered.startAfter(Timestamp.fromMillis(before)) : ordered).limit(pageSize);
}

/**
 * The community feed: the newest posts from public profiles. `before`
 * (ms) pages back; `next` is the cursor for the page after, or null.
 */
export const feed = onCall(options, async (req) => {
  await admit(req);
  const before = parseBefore(input(req).before);
  const snap = await page(getFirestore().collection("posts"), before).get();
  const last = snap.docs.at(-1)?.get("createdAt") as Timestamp | undefined;
  return {
    posts: await publicPosts(snap.docs),
    next: snap.size === pageSize && last ? last.toMillis() : null,
  };
});

/** One post, unless its author is private. */
export const post = onCall(options, async (req) => {
  await admit(req);
  const id = input(req).id;
  if (!validId(id)) throw new HttpsError("invalid-argument", "No such post.");
  const snap = await getFirestore().doc(`posts/${id}`).get();
  const [shown] = snap.exists ? await publicPosts([snap as never]) : [];
  if (!shown) throw new HttpsError("not-found", "This post isn't public.");
  return { post: shown };
});

/** A player's profile and, unless it's private, their newest posts. */
export const profile = onCall(options, async (req) => {
  await admit(req);
  const { uid, before } = input(req);
  if (!validId(uid)) throw new HttpsError("invalid-argument", "No such player.");
  const db = getFirestore();
  const snap = await db.doc(`profiles/${uid}`).get();
  if (!snap.exists) throw new HttpsError("not-found", "No such player.");
  const data = snap.data() as Data;
  if (data.private === true) return { profile: profileView(data), posts: [], next: null };
  const posts = await page(db.collection("posts").where("authorId", "==", uid), parseBefore(before)).get();
  const last = posts.docs.at(-1)?.get("createdAt") as Timestamp | undefined;
  return {
    profile: plain(profileView(data)),
    posts: await publicPosts(posts.docs),
    next: posts.size === pageSize && last ? last.toMillis() : null,
  };
});

/**
 * A team or group's public page: its listing and, unless it's a private
 * group, its public posts and upcoming public events.
 */
export const team = onCall(options, async (req) => {
  await admit(req);
  const id = input(req).id;
  if (!validId(id)) throw new HttpsError("invalid-argument", "No such team.");
  const db = getFirestore();
  const listing = await db.doc(`teamDirectory/${id}`).get();
  if (!listing.exists) throw new HttpsError("not-found", "No such team.");
  const data = listing.data() as Data;
  if (isPrivateGroup(data)) return { listing: plain(listingView(data)), posts: [], events: [] };
  const [posts, events] = await Promise.all([
    db.collection(`teams/${id}/posts`).where("public", "==", true).orderBy("createdAt", "desc").limit(pageSize).get(),
    db
      .collection(`teams/${id}/publicEvents`)
      .where("startsAt", ">=", Timestamp.now())
      .orderBy("startsAt")
      .limit(pageSize)
      .get(),
  ]);
  return {
    listing: plain(listingView(data)),
    posts: posts.docs
      .filter((d) => isPublicTeamPost(d.data()))
      .map((d) => ({ id: d.id, data: plain(teamPostView(d.data())) })),
    events: events.docs.map((d) => ({ id: d.id, data: plain(eventView(d.data())) })),
  };
});

/**
 * What's coming up: public team events across every team that isn't a
 * private group, with each team's listing, and group tournaments.
 */
export const events = onCall(options, async (req) => {
  await admit(req);
  const db = getFirestore();
  const now = Timestamp.now();
  const [eventSnap, tournamentSnap] = await Promise.all([
    db.collectionGroup("publicEvents").where("startsAt", ">=", now).orderBy("startsAt").limit(eventLimit).get(),
    db.collection("tournamentDirectory").where("startsAt", ">=", now).orderBy("startsAt").limit(eventLimit).get(),
  ]);
  const groupOf = (d: { get: (f: string) => unknown }) => d.get("groupId");
  const teamIds = new Set<string>();
  for (const d of eventSnap.docs) if (d.ref.parent.parent) teamIds.add(d.ref.parent.parent.id);
  for (const d of tournamentSnap.docs) {
    const g = groupOf(d);
    if (validId(g)) teamIds.add(g);
  }
  const listings = teamIds.size
    ? new Map(
        (await db.getAll(...[...teamIds].map((id) => db.doc(`teamDirectory/${id}`))))
          .filter((s) => s.exists)
          .map((s) => [s.id, s.data() as Data]),
      )
    : new Map<string, Data>();
  return {
    events: eventSnap.docs.flatMap((d) => {
      const teamId = d.ref.parent.parent?.id ?? "";
      const listing = listings.get(teamId);
      if (isPrivateGroup(listing)) return [];
      return [{ id: d.id, teamId, teamName: listing?.name ?? "", data: plain(eventView(d.data())) }];
    }),
    // Group tournaments' public summaries (TournamentListing), but not a
    // private group's.
    tournaments: tournamentSnap.docs
      .filter((d) => !isPrivateGroup(listings.get(groupOf(d) as string)))
      .map((d) => ({ id: d.id, data: plain(d.data()) })),
  };
});

/**
 * Players or teams by one keyword, as `api-search` takes it. Private
 * profiles show only their card, as they do in the app.
 */
export const search = onCall(options, async (req) => {
  await admit(req);
  const { kind, key: rawKey } = input(req);
  const key = searchKey(rawKey);
  if ((kind !== "players" && kind !== "teams") || !key) {
    throw new HttpsError("invalid-argument", "Nothing to search for.");
  }
  const db = getFirestore();
  if (kind === "teams") {
    const snap = await db.collection("teamDirectory").where("keywords", "array-contains", key).limit(searchLimit).get();
    return { results: snap.docs.map((d) => ({ id: d.id, data: plain(listingView(d.data())) })) };
  }
  // Names only: a private profile's search tags are behind its follow wall.
  const snap = await db.collection("profiles").where("keywords", "array-contains", key).limit(searchLimit).get();
  return { results: snap.docs.map((d) => ({ id: d.id, data: plain(searchProfileView(d.data())) })) };
});
