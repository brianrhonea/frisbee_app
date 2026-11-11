// Imported first by index.ts, so it applies to every function: caps how
// far a flood of requests can scale up (and bill) any one function.
import { setGlobalOptions } from "firebase-functions/v2";

setGlobalOptions({ maxInstances: 10 });

/**
 * Whether callables turn away requests without a valid App Check token.
 * Off until every app build in use sends one (docs/app-check.md); turn it
 * on per project with ENFORCE_APP_CHECK=true in functions/.env.<project>.
 */
export const enforceAppCheck = process.env.ENFORCE_APP_CHECK === "true";
