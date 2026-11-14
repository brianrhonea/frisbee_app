import {
  adultAge,
  ageOn,
  type PersonalDetails,
  type PersonalDetailsResponse,
  type PersonalDetailsStatus,
  personalDetailsProblem,
  personalDetailsRequiredSince,
  personalDetailsSchema,
  tooYoungMessage,
} from "@stall10/shared";
import type { Caller, UserLookup } from "../auth.js";
import { ApiError, fromZod } from "../errors.js";
import { type DocStore, serverTime } from "../store.js";
import type { PersonalCipher } from "./cipher.js";

/** personalDetails/{uid}: closed to every client by firestore.rules. */
export const personalPath = (uid: string) => `personalDetails/${uid}`;

/** The stored record's format, should it ever change. */
const format = 1;

/**
 * A player's own personal details (packages/shared/src/personal.ts). Only
 * the caller reaches their own record: the uid comes from the ID token and
 * there's no way to name anyone else's. Stored as one ciphertext; nothing
 * about them (not even an age) is kept in the clear.
 */
export class PersonalService {
  constructor(
    private readonly store: DocStore,
    private readonly users: UserLookup,
    private readonly cipher: PersonalCipher,
    private readonly now: () => number = Date.now,
  ) {}

  /** Whether they've given them, and whether the apps must ask first. No decryption. */
  async status(caller: Caller): Promise<PersonalDetailsStatus> {
    const [doc, user] = await Promise.all([this.store.get(personalPath(caller.uid)), this.users.lookup(caller.uid)]);
    const created = user?.createdAt ? Date.parse(user.createdAt) : NaN;
    return {
      complete: doc !== null,
      required: Number.isFinite(created) && created >= Date.parse(personalDetailsRequiredSince),
    };
  }

  async get(caller: Caller): Promise<PersonalDetailsResponse> {
    const path = personalPath(caller.uid);
    const [doc, user] = await Promise.all([this.store.get(path), this.users.lookup(caller.uid)]);
    const email = user?.email ?? caller.email ?? null;
    if (!doc) return { details: null, email };
    const plain = await this.cipher.open({ ciphertext: String(doc.ciphertext), key: String(doc.key) }, path);
    return { details: JSON.parse(plain.toString("utf8")) as PersonalDetails, email };
  }

  /** Replaces their details. Under 13 is refused and nothing is saved. */
  async save(caller: Caller, body: unknown): Promise<void> {
    const r = personalDetailsSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const details = r.data;
    // The date in the furthest-ahead time zone (UTC+14): the apps check on
    // the player's own date, so someone who turned 13 or 18 today where
    // they live isn't refused (or asked for a guardian) by a day.
    const today = new Date(this.now() + 14 * 3600_000);
    const problem = personalDetailsProblem(details, today);
    if (problem?.message === tooYoungMessage) {
      throw new ApiError("failed_precondition", tooYoungMessage, { birthDate: tooYoungMessage });
    }
    if (problem) throw new ApiError("invalid_argument", problem.message, { [problem.field]: problem.message });
    // Adults' guardians aren't kept.
    const record: PersonalDetails =
      ageOn(details.birthDate, today) >= adultAge ? { ...details, guardian: undefined } : details;
    const path = personalPath(caller.uid);
    const sealed = await this.cipher.seal(Buffer.from(JSON.stringify(record), "utf8"), path);
    await this.store.transact(async (tx) => {
      tx.set(path, { ciphertext: sealed.ciphertext, key: sealed.key, format, updatedAt: serverTime });
    });
  }
}
