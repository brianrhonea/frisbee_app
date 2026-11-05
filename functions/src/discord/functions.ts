// Discord imports, exported as the `discord` group:
//   firebase deploy --only functions:discord
// Reads public server templates (https://discord.new/...), so it needs no
// bot, token or secret.

import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { type GuildTemplate, mapTemplate, templateCode } from "./template";
import { enforceAppCheck } from "../options";

const validId = (v: unknown): v is string => typeof v === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(v);

/**
 * Reads a Discord server template and returns what importing it would
 * create (ImportPlan): roles, folders and rooms with their access. The
 * team's owner calls it, previews the plan, and the app writes it under
 * firestore.rules like any other edit; this function writes nothing.
 */
export const previewTemplate = onCall({ timeoutSeconds: 30, enforceAppCheck }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to import from Discord.");
  const { teamId, link } = (req.data ?? {}) as Record<string, unknown>;
  if (!validId(teamId)) throw new HttpsError("invalid-argument", "Unknown team.");
  const code = templateCode(link);
  if (code === null) {
    throw new HttpsError("invalid-argument", "Paste a server template link, like https://discord.new/abc123.");
  }

  const team = await getFirestore().doc(`teams/${teamId}`).get();
  const members = (team.data()?.members ?? {}) as Record<string, string>;
  if (members[uid] !== "owner") {
    throw new HttpsError("permission-denied", "Only the owner can import from Discord.");
  }

  let response: Response;
  try {
    response = await fetch(`https://discord.com/api/v10/guilds/templates/${encodeURIComponent(code)}`, {
      headers: { "User-Agent": "frisbee-app (server template import)" },
      signal: AbortSignal.timeout(10_000),
    });
  } catch (e) {
    logger.warn("Discord template fetch failed", { code, error: String(e) });
    throw new HttpsError("unavailable", "Couldn't reach Discord. Try again in a moment.");
  }
  if (response.status === 404) {
    throw new HttpsError("not-found", "Discord doesn't know that template. Check the link, or make a new one.");
  }
  if (response.status === 429) {
    throw new HttpsError("resource-exhausted", "Discord is busy. Try again in a minute.");
  }
  if (!response.ok) {
    logger.warn("Discord template error", { code, status: response.status });
    throw new HttpsError("unavailable", "Discord couldn't load that template.");
  }
  const template = (await response.json()) as GuildTemplate;
  return mapTemplate(template);
});
