import {
  adultOnlyMessage,
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
import { type Data, type DocStore, serverTime } from "../store.js";
import type { PersonalCipher } from "./cipher.js";

/** personalDetails/{uid}: closed to every client by firestore.rules. */
export const personalPath = (uid: string) => `personalDetails/${uid}`;

/**
 * ageRefusals/{uid}: the birth date of a refused under-18 attempt, sealed
 * like personal details (its own path is the cipher's context) and closed to
 * every client by firestore.rules. Only there so a different date can't be
 * tried afterwards (F3); deleted with the account.
 */
export const refusalPath = (uid: string) => `ageRefusals/${uid}`;

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

/** The two messages that refuse a minor's birth date. */
const isMinorMessage = (m: string | undefined): m is typeof tooYoungMessage | typeof adultOnlyMessage => m === tooYoungMessage || m === adultOnlyMessage;

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

  /** Replaces their details. Under 18 is refused and nothing is saved; a saved or refused birth date can't change. */
  async save(caller: Caller, body: unknown): Promise<void> {
    const r = personalDetailsSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const details = r.data;
    // Launch is adults only (the account gate): under 18 is refused, nothing
    // saved but the refusal itself, and no guardian is asked for.
    const problem = personalDetailsProblem(details, this.today());
    if (isMinorMessage(problem?.message)) return this.refuse(caller.uid, details.birthDate, problem.message);
    if (problem) throw new ApiError("invalid_argument", problem.message, { [problem.field]: problem.message });
    // Adults' guardians aren't kept.
    const record: PersonalDetails = { ...details, guardian: undefined };
    const path = personalPath(caller.uid);
    const sealed = await this.cipher.seal(Buffer.from(JSON.stringify(record), "utf8"), path);
    await this.store.transact(async (tx) => {
      const [saved, refusal] = await Promise.all([tx.get(path), tx.get(refusalPath(caller.uid))]);
      await this.requireAllowedDate(caller.uid, saved, refusal, details.birthDate);
      tx.set(path, { ciphertext: sealed.ciphertext, key: sealed.key, format, updatedAt: serverTime });
    });
  }

  /**
   * The birth date is locked once saved (pentest P4: it was changeable
   * 20 times a day, which defeats the club 16+ rule), and a refused one is
   * remembered (F3: otherwise a refused 17-year-old could just try an adult
   * date): a date different from the one [saved] holds, or from the one
   * [refusal] holds, is refused. Re-saving the same one is fine. There is
   * no support override here; deleting the account clears it.
   */
  private async requireAllowedDate(uid: string, saved: Data | null, refusal: Data | null, birthDate: string): Promise<void> {
    const locked = () => new ApiError("failed_precondition", birthDateLockedMessage, { birthDate: birthDateLockedMessage });
    if (saved) {
      const date = await this.openDate(saved, personalPath(uid));
      if (date !== null && date !== birthDate) throw locked();
    }
    if (refusal) {
      const date = await this.openDate(refusal, refusalPath(uid));
      if (date !== null && date !== birthDate) throw locked();
    }
  }

  /** The birth date inside a sealed record, or null when it holds none. */
  private async openDate(doc: Data, path: string): Promise<string | null> {
    const plain = await this.cipher.open({ ciphertext: String(doc.ciphertext), key: String(doc.key) }, path);
    const date = (JSON.parse(plain.toString("utf8")) as { birthDate?: unknown }).birthDate;
    return typeof date === "string" ? date : null;
  }

  /**
   * Refuses a minor's [birthDate] ([message]: under 13 or under 18), always
   * throwing 412. First the locks: a different date than a saved or an
   * earlier refused one is "can't be changed" instead (so an adult can't be
   * disabled by trying a child's date). Otherwise the first refusal is
   * kept sealed (idempotent: a repeat of the same date changes nothing),
   * and an under-13 attempt also disables the Auth account (owner
   * decision; the user is signed out). The disable runs after the record
   * is kept, so a failure there retries to the same end.
   */
  private async refuse(uid: string, birthDate: string, message: string): Promise<never> {
    const sealed = await this.cipher.seal(Buffer.from(JSON.stringify({ birthDate }), "utf8"), refusalPath(uid));
    await this.store.transact(async (tx) => {
      const [saved, refusal] = await Promise.all([tx.get(personalPath(uid)), tx.get(refusalPath(uid))]);
      await this.requireAllowedDate(uid, saved, refusal, birthDate);
      // `under13` is a plain marker (no birth date in it) so the scheduled purge in the functions, which can't open the sealed date, knows which refusals to act on.
      if (!refusal) {
        tx.set(refusalPath(uid), {
          ciphertext: sealed.ciphertext,
          key: sealed.key,
          format,
          refusedAt: serverTime,
          ...(message === tooYoungMessage && { under13: true }),
        });
      }
    });
    if (message === tooYoungMessage) await this.users.setDisabled?.(uid, true);
    throw new ApiError("failed_precondition", message, { birthDate: message });
  }

  /**
   * Keeps the email sign-up form's birthday until "About you" is filled
   * in, encrypted like the full details, so it isn't asked again after a
   * restart or on another device. Checked as the full save checks it
   * (under 18 refused and remembered, nothing else saved). Only while the
   * details aren't complete: once they are, it's refused and changes
   * nothing, so it can't replace a saved birthday. The full save replaces
   * this record whole.
   */
  async saveSignUpBirthDate(caller: Caller, body: unknown): Promise<void> {
    const r = signUpBirthDateSchema.safeParse(body ?? {});
    if (!r.success) throw fromZod(r.error);
    const { birthDate } = r.data;
    const problem = birthDateProblem(birthDate, this.today());
    if (isMinorMessage(problem ?? undefined)) return this.refuse(caller.uid, birthDate, problem!);
    if (problem) throw new ApiError("invalid_argument", problem, { birthDate: problem });
    const path = personalPath(caller.uid);
    const sealed = await this.cipher.seal(Buffer.from(JSON.stringify({ birthDate }), "utf8"), path);
    await this.store.transact(async (tx) => {
      const [doc, refusal] = await Promise.all([tx.get(path), tx.get(refusalPath(caller.uid))]);
      if (doc && !isBirthDateOnly(doc)) {
        throw new ApiError("already_exists", "Your details are already saved. Change them in Settings.");
      }
      await this.requireAllowedDate(caller.uid, doc, refusal, birthDate);
      tx.set(path, { ciphertext: sealed.ciphertext, key: sealed.key, format, [birthDateOnly]: true, updatedAt: serverTime });
    });
  }

  /**
   * The date in the furthest-ahead time zone (UTC+14): the apps check on
   * the player's own date, so someone who turned 13 or 18 today where
   * they live isn't refused by a day.
   */
  private today(): Date {
    return new Date(this.now() + 14 * 3600_000);
  }

  /**
   * Whether [uid]'s Auth account was disabled by an under-13 refusal (N4):
   * the remembered birth date made them under 13 when it was refused. A
   * suspension being lifted must not re-enable it (no staff override).
   */
  async disabledForAge(uid: string): Promise<boolean> {
    const refusal = await this.store.get(refusalPath(uid));
    if (!refusal) return false;
    const date = await this.openDate(refusal, refusalPath(uid));
    // A refusal whose date can't be read can't be shown to be anything but an under-13 one: fail closed (stay disabled).
    if (date === null) return true;
    // A refusedAt that isn't a Date can't be trusted: judge the age on the birth date itself (age 0, under 13), so the account stays disabled (review 4.1d).
    const at = refusal.refusedAt instanceof Date ? refusal.refusedAt : new Date(`${date}T00:00:00Z`);
    return birthDateProblem(date, at) === tooYoungMessage;
  }
}
