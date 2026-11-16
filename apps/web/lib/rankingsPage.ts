import type { PublicRankings } from "@stall10/shared";
import { cache } from "react";
import { getPublicOrNull } from "./api";

/**
 * Every team ranking visitors may see (`/v1/public/rankings`: never
 * youth), or null when the API can't answer, so members still get their
 * live rankings.
 */
export const loadRankings = cache(async (): Promise<PublicRankings | null> => {
  try {
    return await getPublicOrNull<PublicRankings>("/v1/public/rankings");
  } catch {
    return null;
  }
});
