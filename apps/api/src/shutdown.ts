// Graceful shutdown. Cloud Run sends SIGTERM and kills the instance 10
// seconds later: stop taking requests (Fastify answers new ones with 503
// while closing), let in-flight ones finish, then exit.
import type { FastifyInstance } from "fastify";

export interface ShutdownOptions {
  /** Give up and exit(1) after this long; under Cloud Run's 10 s. */
  timeoutMs?: number;
  exit?: (code: number) => void;
}

/** Returns the handler; [closeOnSignals] wires it to the process. */
export function shutdownHandler(app: FastifyInstance, opts: ShutdownOptions = {}) {
  const exit = opts.exit ?? ((code: number) => process.exit(code));
  const timeoutMs = opts.timeoutMs ?? 8000;
  let closing: Promise<void> | null = null;

  return (signal: string): Promise<void> => {
    closing ??= (async () => {
      app.log.info({ signal }, "shutting down");
      const timer = setTimeout(() => {
        app.log.error({ timeoutMs }, "shutdown timed out");
        exit(1);
      }, timeoutMs);
      timer.unref();
      try {
        await app.close();
        clearTimeout(timer);
        exit(0);
      } catch (err) {
        clearTimeout(timer);
        app.log.error({ err }, "shutdown failed");
        exit(1);
      }
    })();
    return closing;
  };
}

export function closeOnSignals(app: FastifyInstance, opts: ShutdownOptions = {}) {
  const handler = shutdownHandler(app, opts);
  for (const signal of ["SIGTERM", "SIGINT"] as const) {
    process.once(signal, () => void handler(signal));
  }
  return handler;
}
