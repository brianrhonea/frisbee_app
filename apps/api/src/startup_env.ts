// Startup environment assertions (audit INF-6). Run once from server.ts,
// before Firebase Admin is initialised, so a misconfigured deploy fails
// fast with a clear message instead of quietly talking to the wrong project.
//
// "Deployed" means NODE_ENV=production (the Dockerfile sets it) or K_SERVICE
// (Cloud Run sets it). A local `pnpm dev` sets neither, so local runs keep
// the dev project as the default and need no extra environment.
//
// Messages name variables, never values: a key must not reach the logs.

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
  const deployed = isDeployed(env);
  const explicit = env.FIREBASE_PROJECT_ID?.trim();
  if (deployed && !explicit) {
    throw new StartupConfigError(
      "FIREBASE_PROJECT_ID must be set explicitly when deployed (NODE_ENV=production or on Cloud Run). Refusing to fall back to the dev project.",
    );
  }
  const projectId = explicit || DEV_PROJECT_ID;

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
