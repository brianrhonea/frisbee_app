import type { User } from "firebase/auth";
import { ApiError, callApi } from "./client";
import { newId } from "./upload";

/** A client-made id for a new event: `^[A-Za-z0-9]{1,40}$`, the API's rule (20 characters here). */
export const newEventId = newId;

/**
 * POSTs a new event with its client-made [id] in the body. A replay of the same id is a 409 `already_exists`
 * (the first try did land, e.g. a retry or double-click after a lost answer): that is a success, with the id
 * the event already has. Any other failure is thrown as it is.
 */
export async function postNewEvent(user: User, path: string, body: Record<string, unknown>, id: string): Promise<{ id: string }> {
  try {
    const res = await callApi<{ id?: string }>(user, path, { method: "POST", body: { ...body, id } });
    return { id: res?.id ?? id };
  } catch (e) {
    if (e instanceof ApiError && e.status === 409 && (e.code === undefined || e.code === "already_exists")) return { id };
    throw e;
  }
}
