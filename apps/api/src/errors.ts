import { type ApiErrorBody, type ApiErrorCode, apiErrorStatus } from "@stall10/shared";
import type { FastifyError, FastifyReply, FastifyRequest } from "fastify";
import { ZodError } from "zod";

/** A request the API turns down, with a message ready to show the user. */
export class ApiError extends Error {
  constructor(
    readonly code: ApiErrorCode,
    message: string,
    readonly fields?: Record<string, string>,
  ) {
    super(message);
  }

  get status(): number {
    return apiErrorStatus[this.code];
  }

  toBody(): ApiErrorBody {
    return { error: { code: this.code, message: this.message, ...(this.fields && { fields: this.fields }) } };
  }
}

/** Turns zod issues into one invalid_argument error. */
export function fromZod(e: ZodError): ApiError {
  const fields: Record<string, string> = {};
  for (const issue of e.issues) {
    const key = issue.path.join(".") || "_";
    fields[key] ??= issue.message;
  }
  // The first problem, as the app shows it: our own messages as written,
  // zod's prefixed with the field they're about.
  const [key, msg] = Object.entries(fields)[0] ?? ["_", "Invalid request."];
  const custom = e.issues[0]?.code === "custom" || /^[A-Z].*\.$/.test(msg);
  return new ApiError("invalid_argument", custom || key === "_" ? msg : `${key}: ${msg}`, fields);
}

/** Fastify error handler: every error leaves as an ApiErrorBody. */
export function errorHandler(err: FastifyError | Error, req: FastifyRequest, reply: FastifyReply) {
  let api: ApiError;
  if (err instanceof ApiError) {
    api = err;
  } else if (err instanceof ZodError) {
    api = fromZod(err);
  } else if ("statusCode" in err && typeof err.statusCode === "number" && err.statusCode < 500) {
    // Fastify's own 4xx (bad JSON, body too large…).
    api = new ApiError("invalid_argument", err.message);
  } else {
    req.log.error({ err }, "unhandled error");
    api = new ApiError("internal", "Something went wrong. Try again.");
  }
  return reply.status(api.status).send(api.toBody());
}
