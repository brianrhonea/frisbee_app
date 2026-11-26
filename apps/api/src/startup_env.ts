// Startup environment assertions (audit INF-6). Run once from server.ts,
// before Firebase Admin is initialised, so a misconfigured deploy fails
// fast with a clear message instead of quietly talking to the wrong project.
//
// "Deployed" means NODE_ENV=production (the Dockerfile sets it) or K_SERVICE
// (Cloud Run sets it). A local `pnpm dev` sets neither, so local runs keep
// the dev project as the default and need no extra environment.
//
// Messages name variables, never values: a key must not reach the logs.

import type { AccountGateMode } from "./auth.js";

export const DEV_PROJECT_ID = "frisbee-app-brianrhonea-dev";
export const PROD_PROJECT_ID = "frisbee-app-brianrhonea";

export class StartupConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "StartupConfigError";
  }
}

type Env = Record<string, string | undefined>;

/** Cloud Run (K_SERVICE) or a production build (NODE_ENV=production). */
export function isDeployed(env: Env = process.env): boolean {
  return Boolean(env.K_SERVICE?.trim()) || env.NODE_ENV === "production";
}

const EMULATOR_HOST_VARS = ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"] as const;

/**
 * On Cloud Run (K_SERVICE) no emulator variable may be present: the Admin SDK
 * would accept unsigned emulator tokens and the emulator waivers below would
 * skip the KMS and gate checks (security review 3.1). Names only, never values.
 */
export function assertNoEmulatorOnCloudRun(env: Env = process.env): void {
  if (!env.K_SERVICE?.trim()) return;
  const present = EMULATOR_HOST_VARS.filter((k) => env[k] !== undefined && env[k]!.trim() !== "");
  if (present.length > 0) {
    throw new StartupConfigError(`${present.join(", ")} must not be set on Cloud Run (K_SERVICE is set): emulator settings are for local runs only.`);
  }
}

/** "live" for sk_live_/rk_live_, "test" for sk_test_/rk_test_, else unknown. */
export function stripeKeyMode(key: string): "live" | "test" | "unknown" {
  if (key.startsWith("sk_live_") || key.startsWith("rk_live_")) return "live";
  if (key.startsWith("sk_test_") || key.startsWith("rk_test_")) return "test";
  return "unknown";
}

/**
 * The Firebase project this process talks to. Deployed: FIREBASE_PROJECT_ID
 * must be set (no silent dev fallback). Stripe's mode must match it: live
 * keys only with the production project, test keys only with any other.
 * Throws StartupConfigError.
 */
export function assertStartupEnvironment(env: Env = process.env): string {
  assertNoEmulatorOnCloudRun(env);
  const deployed = isDeployed(env);
  const explicit = env.FIREBASE_PROJECT_ID?.trim();
  if (deployed && !explicit) {
    throw new StartupConfigError(
      "FIREBASE_PROJECT_ID must be set explicitly when deployed (NODE_ENV=production or on Cloud Run). Refusing to fall back to the dev project.",
    );
  }
  const projectId = explicit || DEV_PROJECT_ID;

  // Without the personal-details key every age check fails closed: the web
  // sign-up gate would turn every member away. Emulators use a local key.
  const emulated = Boolean(env.FIRESTORE_EMULATOR_HOST?.trim() || env.FIREBASE_AUTH_EMULATOR_HOST?.trim());
  if (deployed && !emulated && !env.PERSONAL_DETAILS_KMS_KEY?.trim()) {
    throw new StartupConfigError("PERSONAL_DETAILS_KMS_KEY must be set when deployed: without it date-of-birth checks fail closed and block every member.");
  }

  // F8: with the gate enforcing, no cipher means nobody's birth date can be
  // opened, so no account ever earns `ageOk` and every write is refused. Fail at
  // boot rather than lock everyone out (report-only runs without one, locally).
  const mode = accountGateModeFromEnv(env);
  if (mode === "enforce" && !env.PERSONAL_DETAILS_KMS_KEY?.trim() && !env.PERSONAL_DETAILS_LOCAL_KEY?.trim()) {
    throw new StartupConfigError("PERSONAL_DETAILS_KMS_KEY (or PERSONAL_DETAILS_LOCAL_KEY with the emulators) must be set when ACCOUNT_GATE_MODE=enforce: without a cipher no account can earn the age claim.");
  }

  const key = env.STRIPE_SECRET_KEY?.trim();
  if (key) {
    const mode = stripeKeyMode(key);
    if (mode === "unknown") {
      if (deployed) throw new StartupConfigError("STRIPE_SECRET_KEY isn't a Stripe sk_/rk_ live or test key (expected an sk_live_, sk_test_, rk_live_ or rk_test_ prefix).");
    } else if (mode === "live" && projectId !== PROD_PROJECT_ID) {
      throw new StartupConfigError(`STRIPE_SECRET_KEY is a live key but FIREBASE_PROJECT_ID is ${projectId}: live keys are only for ${PROD_PROJECT_ID}.`);
    } else if (mode === "test" && projectId === PROD_PROJECT_ID) {
      throw new StartupConfigError(`STRIPE_SECRET_KEY is a test key but FIREBASE_PROJECT_ID is ${PROD_PROJECT_ID}: production needs a live key (or no Stripe key, to leave payments off).`);
    }
  }
  return projectId;
}

/**
 * How the API treats a write by an incomplete account (ACCOUNT_GATE_MODE,
 * docs/specifications/contracts/account-gate.md): `report` (the local/emulator default,
 * when unset; deployed, an unset value is a startup error) logs account_incomplete and lets it through, so the first
 * rollout can't lock anyone out while the claims and clients catch up;
 * `enforce` refuses it with 403 account_incomplete. Anything else is a
 * startup error, so a typo can't quietly turn the gate off. The claims are
 * set, and age and birth-date rules enforced, in both modes. Throws StartupConfigError.
 */
export function accountGateModeFromEnv(env: Env = process.env): AccountGateMode {
  assertNoEmulatorOnCloudRun(env);
  const v = env.ACCOUNT_GATE_MODE?.trim().toLowerCase();
  if (!v) {
    // Deployed (and not emulated, as for the KMS key): an explicit value, so a missing variable can't quietly leave the gate report-only (N3).
    if (isDeployed(env) && !(env.FIRESTORE_EMULATOR_HOST?.trim() || env.FIREBASE_AUTH_EMULATOR_HOST?.trim())) {
      throw new StartupConfigError("ACCOUNT_GATE_MODE must be set to enforce or report when deployed.");
    }
    return "report";
  }
  if (v === "enforce" || v === "report") return v;
  throw new StartupConfigError("ACCOUNT_GATE_MODE must be enforce or report.");
}
