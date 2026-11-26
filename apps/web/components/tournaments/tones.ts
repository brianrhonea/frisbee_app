import type { StatusTone } from "../ui/StatusPill";

/** A competition entry's pill tone: accepted is good, declined is a refusal. */
export function entryTone(status: string): StatusTone {
  switch (status) {
    case "accepted":
      return "success";
    case "applied":
    case "invited":
      return "accent";
    case "declined":
      return "error";
    default:
      return "neutral";
  }
}

/** A hosted competition's status pill tone: sign-ups open, live now, the rest quiet. */
export function hostedTone(status: string): StatusTone {
  return status === "registration" ? "success" : status === "live" ? "live" : "neutral";
}
