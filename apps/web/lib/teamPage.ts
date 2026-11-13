import type { TeamPage } from "@stall10/shared";
import { cache } from "react";
import { getPublic } from "./api";

/** A team's public page (`/v1/public/teams/:id`), once per request for the hub's layout and section. */
export const loadTeam = cache((id: string) => getPublic<TeamPage>(`/v1/public/teams/${encodeURIComponent(id)}`));
