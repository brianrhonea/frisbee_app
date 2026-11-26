import {
  adultAge,
  adultOnlyMessage,
  ageOn,
  birthDateLockedMessage,
  birthDateProblem,
  type PersonalDetails,
  type PersonalDetailsResponse,
  type PersonalDetailsStatus,
  personalDetailsProblem,
  personalDetailsRequiredSince,
  personalDetailsSchema,
  signUpBirthDateSchema,
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
 * Marks a record holding only the sign-up form's birthday
 * ([PersonalService.saveSignUpBirthDate]): the ciphertext is
 * `{"birthDate":…}`, sealed exactly like full details, and the details
 * aren't complete until the full form replaces it.
 */
const birthDateOnly = "birthDateOnly";
const isBirthDateOnly = (doc: Record<string, unknown> | null) => doc?.[birthDateOnly] === true;

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
      complete: doc !== null && !isBirthDateOnly(doc),
      required: Number.isFinite(created) && created >= Date.parse(personalDetailsRequiredSince),
    };
  }

  async get(caller: Caller): Promise<PersonalDetailsResponse> {
    const path = personalPath(caller.uid);
    const [doc, user] = await Promise.all([this.store.get(path), this.users.lookup(caller.uid)]);
    const email = user?.email ?? caller.email ?? null;
    if (!doc) return { details: null, email };
    const plain = await this.cipher.open({ ciphertext: String(doc.ciphertext), key: String(doc.key) }, path);
    const record = JSON.parse(plain.toString("utf8"));
    if (isBirthDateOnly(doc)) {
      const { birthDate } = record as { birthDate?: unknown };
      return { details: null, email, ...(typeof birthDate === "string" && { signUpBirthDate: birthDate }) };
    }
    return { details: record as PersonalDetails, email };
  }

  /**
   * [uid]'s date of birth (YYYY-MM-DD), or null when they haven't given
   * their details, for the API's own age checks (club teams: teams/
   * club_age.ts). Never sent to anyone: callers only learn yes or no.
   */
  async birthDate(uid: string): Promise<string | null> {
    const path = personalPath(uid);
    const doc = await this.store.get(path);
    if (!doc) return null;
    const plain = await this.cipher.open({ ciphertext: String(doc.ciphertext), key: String(doc.key) }, path);
    const birthDate = (JSON.parse(plain.toString("utf8")) as Partial<PersonalDetails>).birthDate;
    return typeof birthDate === "string" ? birthDate : null;
  }

  /** Replaces their details. Under 18 is refused and nothing is saved; a saved birth date can't change. */
  async save(caller: Caller, body: unknown): Promise<void> {
    const r = personalDetailsSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const details = r.data;
    const today = this.today();
    const problem = personalDetailsProblem(details, today);
    if (problem?.message === tooYoungMessage) {
      throw new ApiError("failed_precondition", tooYoungMessage, { birthDate: tooYoungMessage });
    }
    // Launch is adults only (the account gate): under 18 is refused, nothing
    // saved, whatever else is wrong (a 17-year-old isn't asked for a guardian).
    if (problem?.field !== "birthDate" && ageOn(details.birthDate, today) < adultAge) {
      throw new ApiError("failed_precondition", adultOnlyMessage, { birthDate: adultOnlyMessage });
    }
    if (problem) throw new ApiError("invalid_argument", problem.message, { [problem.field]: problem.message });
    // Adults' guardians aren't kept.
    const record: PersonalDetails = { ...details, guardian: undefined };
    const path = personalPath(caller.uid);
    const sealed = await this.cipher.seal(Buffer.from(JSON.stringify(record), "utf8"), path);
    await this.store.transact(async (tx) => {
      await this.requireSameBirthDate(await tx.get(path), details.birthDate, path);
      tx.set(path, { ciphertext: sealed.ciphertext, key: sealed.key, format, updatedAt: serverTime });
    });
  }

  /**
   * The birth date is locked once saved (pentest P4: it was changeable
   * 20 times a day, which defeats the club 16+ rule): a save that names a
   * different one than [existing] holds is refused. Re-saving the same one
   * is fine. There is no support override here; deleting the account
   * clears it.
   */
  private async requireSameBirthDate(existing: Record<string, unknown> | null, birthDate: string, path: string): Promise<void> {
    if (!existing) return;
    const plain = await this.cipher.open({ ciphertext: String(existing.ciphertext), key: String(existing.key) }, path);
    const saved = (JSON.parse(plain.toString("utf8")) as { birthDate?: unknown }).birthDate;
    if (typeof saved === "string" && saved !== birthDate) {
      throw new ApiError("failed_precondition", birthDateLockedMessage, { birthDate: birthDateLockedMessage });
    }
  }

  /**
   * Keeps the email sign-up form's birthday until "About you" is filled
   * in, encrypted like the full details, so it isn't asked again after a
   * restart or on another device. Checked as the full save checks it
   * (under 13 refused, nothing saved). Only while the details aren't
   * complete: once they are, it's refused and changes nothing, so it can't
   * replace a saved birthday. The full save replaces this record whole.
   */
  async saveSignUpBirthDate(caller: Caller, body: unknown): Promise<void> {
    const r = signUpBirthDateSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const { birthDate } = r.data;
    const problem = birthDateProblem(birthDate, this.today());
    if (problem === tooYoungMessage) {
      throw new ApiError("failed_precondition", tooYoungMessage, { birthDate: tooYoungMessage });
    }
    if (problem) throw new ApiError("invalid_argument", problem, { birthDate: problem });
    if (ageOn(birthDate, this.today()) < adultAge) {
      throw new ApiError("failed_precondition", adultOnlyMessage, { birthDate: adultOnlyMessage });
    }
    const path = personalPath(caller.uid);
    const sealed = await this.cipher.seal(Buffer.from(JSON.stringify({ birthDate }), "utf8"), path);
    await this.store.transact(async (tx) => {
      const doc = await tx.get(path);
      if (doc && !isBirthDateOnly(doc)) {
        throw new ApiError("already_exists", "Your details are already saved. Change them in Settings.");
      }
      await this.requireSameBirthDate(doc, birthDate, path);
      tx.set(path, { ciphertext: sealed.ciphertext, key: sealed.key, format, [birthDateOnly]: true, updatedAt: serverTime });
    });
  }

  /**
   * The date in the furthest-ahead time zone (UTC+14): the apps check on
   * the player's own date, so someone who turned 13 or 18 today where
   * they live isn't refused (or asked for a guardian) by a day.
   */
  private today(): Date {
    return new Date(this.now() + 14 * 3600_000);
  }
}
