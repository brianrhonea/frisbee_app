import {
  claimUsernameRequestSchema,
  type MessagePolicy,
  messagePolicies,
  messagePolicyRequestSchema,
  normalizeUsername,
  privateProfileFields,
  profileDetailsRequestSchema,
  profileKeywords,
  profileLimits,
  profilePrivacyRequestSchema,
  profileVisibilityRequestSchema,
  usernameProblem,
  usernameTakenMessage,
} from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, parseBody } from "../errors.js";
import { type Data, type DocStore, deleteField, serverTime } from "../store.js";
import { clip } from "../teams/access.js";

const p = {
  profile: (uid: string) => `profiles/${uid}`,
  hidden: (uid: string) => `profiles/${uid}/private/details`,
  username: (name: string) => `usernames/${name}`,
  user: (uid: string) => `users/${uid}`,
};

const usernameOf = (profile: Data | null) => (typeof profile?.username === "string" ? profile.username : null);

/**
 * The caller's own profile (profiles/{uid}, and private/details when it's
 * private) and username. Ports the checks of firestore.rules' profiles
 * rule (validProfile: shape and limits; owner only; a username set once,
 * with its usernames/{name} claim) and the usernames create rule (format,
 * uniqueness). Directory fields (name, keywords, photo) come from the Auth
 * record, never the body. Each write merges, as the app's did.
 */
export class ProfileService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
  ) {}

  /** The caller's name and photo as their Auth record has them. */
  private async who(caller: Caller): Promise<{ name: string; photoUrl: string | null }> {
    const user = await this.users.lookup(caller.uid);
    // Never the email: it isn't public (base() falls back to the username).
    const name = clip(((user ? user.name : caller.name) ?? "").trim(), profileLimits.name);
    return { name, photoUrl: user?.photoUrl ?? null };
  }

  /** The directory fields every profile write carries (_base in the app). */
  private static base(who: { name: string; photoUrl: string | null }, username: string | null, tags: string[], caller: Caller): Data {
    const name = who.name || username || "Player";
    return {
      name,
      keywords: profileKeywords(name, username),
      photoUrl: who.photoUrl,
      tags,
      // Server-only (firestore.rules): set from the age claim, never written false (D-1317).
      ...(caller.ageOk === true && { adult: true }),
      updatedAt: serverTime,
    };
  }

  /**
   * Claims [username] for the caller: free (usernames/{name} doesn't
   * exist), valid (Username.problem), and only if they have none yet. The
   * claim and the profile's username are written together.
   */
  async claimUsername(caller: Caller, body: unknown): Promise<{ username: string }> {
    const handle = normalizeUsername(parseBody(claimUsernameRequestSchema, body).username);
    const problem = usernameProblem(handle);
    if (problem) throw new ApiError("invalid_argument", `${problem}.`, { username: problem });
    const user = await this.users.lookup(caller.uid);
    // Never list an email as someone's name.
    const display = user?.name?.trim() ?? "";
    const name = clip(display || handle, profileLimits.name);
    await this.store.transact(async (tx) => {
      const claim = await tx.get(p.username(handle));
      const profile = await tx.get(p.profile(caller.uid));
      const current = usernameOf(profile);
      if (claim) {
        if (claim.uid === caller.uid && current === handle) return;
        throw new ApiError("already_exists", usernameTakenMessage(handle));
      }
      if (current != null) throw new ApiError("failed_precondition", `You're already @${current}.`);
      tx.create(p.username(handle), { uid: caller.uid, createdAt: serverTime });
      tx.merge(p.profile(caller.uid), {
        name,
        keywords: profileKeywords(name, handle),
        photoUrl: user?.photoUrl ?? null,
        username: handle,
        ...(caller.ageOk === true && { adult: true }),
        updatedAt: serverTime,
      });
    });
    return { username: handle };
  }

  /** Saves what the player wrote about themselves, on the private doc if the profile is private. */
  async saveDetails(caller: Caller, body: unknown): Promise<void> {
    const { tags, ...details } = parseBody(profileDetailsRequestSchema, body);
    const who = await this.who(caller);
    await this.store.transact(async (tx) => {
      // Read in the transaction, so a privacy change can't slip between.
      const profile = await tx.get(p.profile(caller.uid));
      const isPrivate = profile?.private === true;
      const base = ProfileService.base(who, usernameOf(profile), isPrivate ? [] : tags, caller);
      if (isPrivate) {
        tx.merge(p.profile(caller.uid), base);
        tx.merge(p.hidden(caller.uid), { ...details, tags, updatedAt: serverTime });
      } else {
        tx.merge(p.profile(caller.uid), { ...base, ...details });
      }
    });
  }

  /**
   * Makes the profile private (its details, summary and tags move to
   * private/details) or public again (they move back). Nothing to do if
   * it's already that way.
   */
  async setPrivate(caller: Caller, body: unknown): Promise<void> {
    const { private: makePrivate } = parseBody(profilePrivacyRequestSchema, body);
    const who = await this.who(caller);
    await this.store.transact(async (tx) => {
      const profile = (await tx.get(p.profile(caller.uid))) ?? {};
      const hidden = (await tx.get(p.hidden(caller.uid))) ?? {};
      const base = ProfileService.base(who, usernameOf(profile), [], caller);
      if ((profile.private === true) === makePrivate && Object.keys(profile).length > 0) return;
      if (makePrivate) {
        const moved: Data = {};
        for (const f of privateProfileFields) if (f in profile) moved[f] = profile[f];
        tx.set(p.hidden(caller.uid), { ...moved, updatedAt: serverTime });
        const cleared: Data = {};
        for (const f of privateProfileFields) if (f !== "tags") cleared[f] = deleteField;
        tx.merge(p.profile(caller.uid), { ...base, private: true, ...cleared });
      } else {
        const { updatedAt: _, tags, ...data } = hidden;
        const back = Array.isArray(tags) ? tags.filter((t) => typeof t === "string") : [];
        tx.merge(p.profile(caller.uid), { ...base, tags: back, ...data, private: false });
        tx.delete(p.hidden(caller.uid));
      }
    });
  }

  /**
   * Which sections others see. Hidden ones are emptied at once; the app
   * republishes shown ones with its next summary.
   */
  async saveVisibility(caller: Caller, body: unknown): Promise<void> {
    const { visibility, tags } = parseBody(profileVisibilityRequestSchema, body);
    const fields: Data = {
      visibility,
      tags,
      ...(!visibility.stats && { stats: {} }),
      ...(!visibility.games && { games: [] }),
      ...(!visibility.teams && { teams: [] }),
      // Per-team stats say which teams they're on: gone with either hidden.
      ...((!visibility.stats || !visibility.teams) && { teamStats: deleteField }),
    };
    const who = await this.who(caller);
    await this.store.transact(async (tx) => {
      const profile = await tx.get(p.profile(caller.uid));
      const isPrivate = profile?.private === true;
      const base = ProfileService.base(who, usernameOf(profile), tags, caller);
      if (isPrivate) tx.merge(p.hidden(caller.uid), { ...fields, updatedAt: serverTime });
      else tx.merge(p.profile(caller.uid), { ...base, ...fields });
    });
  }

  /** Who may start a conversation with them (users/{uid}.messagePolicy; default everyone). */
  async messagePolicy(caller: Caller): Promise<{ messagePolicy: MessagePolicy }> {
    const v = (await this.store.get(p.user(caller.uid)))?.messagePolicy;
    return { messagePolicy: messagePolicies.includes(v as MessagePolicy) ? (v as MessagePolicy) : "everyone" };
  }

  /** Sets it on their own users doc, as the app's Settings does (merge). */
  async setMessagePolicy(caller: Caller, body: unknown): Promise<void> {
    const { messagePolicy } = parseBody(messagePolicyRequestSchema, body);
    await this.store.transact(async (tx) => {
      tx.merge(p.user(caller.uid), { messagePolicy });
    });
  }
}
