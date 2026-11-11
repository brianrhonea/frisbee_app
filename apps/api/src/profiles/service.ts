import {
  claimUsernameRequestSchema,
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
import type { z } from "zod";
import { type Caller, callerLabel, type UserLookup } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { type Data, type DocStore, deleteField, serverTime } from "../store.js";

const p = {
  profile: (uid: string) => `profiles/${uid}`,
  hidden: (uid: string) => `profiles/${uid}/private/details`,
  username: (name: string) => `usernames/${name}`,
};

function parse<S extends z.ZodType>(schema: S, body: unknown): z.output<S> {
  const r = schema.safeParse(body ?? {});
  if (!r.success) throw fromZod(r.error);
  return r.data;
}

const clip = (s: string, max: number) => (s.length > max ? s.substring(0, max) : s);
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

  /** The directory fields every profile write carries (_base in the app). */
  private async base(caller: Caller, username: string | null, tags: string[]): Promise<Data> {
    const user = await this.users.lookup(caller.uid);
    const name = clip(callerLabel({ uid: caller.uid, ...(user ?? { name: caller.name, email: caller.email }) }), profileLimits.name);
    return {
      name,
      keywords: profileKeywords(name, username),
      photoUrl: user?.photoUrl ?? null,
      tags,
      updatedAt: serverTime,
    };
  }

  /**
   * Claims [username] for the caller: free (usernames/{name} doesn't
   * exist), valid (Username.problem), and only if they have none yet. The
   * claim and the profile's username are written together.
   */
  async claimUsername(caller: Caller, body: unknown): Promise<{ username: string }> {
    const handle = normalizeUsername(parse(claimUsernameRequestSchema, body).username);
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
        updatedAt: serverTime,
      });
    });
    return { username: handle };
  }

  /** Saves what the player wrote about themselves, on the private doc if the profile is private. */
  async saveDetails(caller: Caller, body: unknown): Promise<void> {
    const { tags, ...details } = parse(profileDetailsRequestSchema, body);
    const profile = await this.store.get(p.profile(caller.uid));
    const username = usernameOf(profile);
    const isPrivate = profile?.private === true;
    const base = await this.base(caller, username, isPrivate ? [] : tags);
    await this.store.transact(async (tx) => {
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
    const { private: makePrivate } = parse(profilePrivacyRequestSchema, body);
    const before = await this.store.get(p.profile(caller.uid));
    const base = await this.base(caller, usernameOf(before), []);
    await this.store.transact(async (tx) => {
      const profile = (await tx.get(p.profile(caller.uid))) ?? {};
      const hidden = (await tx.get(p.hidden(caller.uid))) ?? {};
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
    const { visibility, tags } = parse(profileVisibilityRequestSchema, body);
    const profile = await this.store.get(p.profile(caller.uid));
    const isPrivate = profile?.private === true;
    const fields: Data = {
      visibility,
      tags,
      ...(!visibility.stats && { stats: {} }),
      ...(!visibility.games && { games: [] }),
      ...(!visibility.teams && { teams: [] }),
    };
    const base = await this.base(caller, usernameOf(profile), tags);
    await this.store.transact(async (tx) => {
      if (isPrivate) tx.merge(p.hidden(caller.uid), { ...fields, updatedAt: serverTime });
      else tx.merge(p.profile(caller.uid), { ...base, ...fields });
    });
  }
}
