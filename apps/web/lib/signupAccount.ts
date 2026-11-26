"use client";
import type { SignUpBirthDateInput } from "@stall10/shared";
import type { User } from "firebase/auth";
import { ApiError, callApi } from "./client";

/**
 * What email sign-up does with the API once the account exists, in the order
 * the account gate needs (account-gate.md, review finding F1): the birth
 * date first (the API sets the `ageOk` claim and answers `refreshToken:
 * true`, which callApi acts on), and only then the username, which the API
 * refuses without `ageOk`. If the birth date isn't saved (offline, or the
 * server refuses it), the username is not attempted: the gate asks for the
 * birth date, then the username, in that order.
 *
 * Returns whether the birth date was saved. A 412 (under 18) is returned as
 * "adultOnly" so the caller can show the dead end.
 */
export async function saveSignUpDetails(user: User, birthDate: string, handle: string): Promise<"saved" | "adultOnly" | "skipped"> {
  const body: SignUpBirthDateInput = { birthDate };
  try {
    await callApi(user, "/v1/me/personal/birth-date", { method: "PUT", body });
  } catch (err) {
    if (err instanceof ApiError && err.status === 412 && err.fields?.birthDate) return "adultOnly";
    return "skipped";
  }
  try {
    await callApi(user, "/v1/me/username", { method: "POST", body: { username: handle } });
  } catch (err) {
    // Taken in the meantime, or the API is down: the next step asks again.
    if (!(err instanceof ApiError)) throw err;
  }
  return "saved";
}
