"use client";
// The app's in-app payments setup (/embed/payouts in its WebView):
//
//   app → page   window.stall10StartPayouts("<client secret>")
//   page → app   Stall10Payouts.postMessage("ready" | "exit" | "error")
//
// The app registers the Stall10Payouts JavaScript channel, waits for
// "ready", then calls stall10StartPayouts with the secret from
// POST /v1/teams/:teamId/payouts/session. "exit" means the person finished
// or closed Stripe's form: the app closes this view and reloads the status.
// ?view=manage shows the linked account's bank details and payouts instead.
import { useEffect, useState } from "react";
import { EmbeddedOnboarding } from "./Payments";

type Channel = { postMessage: (message: string) => void };
type EmbedWindow = Window & { Stall10Payouts?: Channel; stall10StartPayouts?: (clientSecret: string) => void };

const tell = (message: "ready" | "exit" | "error") => (window as EmbedWindow).Stall10Payouts?.postMessage(message);

export function EmbeddedPayouts() {
  const [secret, setSecret] = useState<string | null>(null);
  useEffect(() => {
    const w = window as EmbedWindow;
    w.stall10StartPayouts = (clientSecret: string) => {
      if (typeof clientSecret === "string" && clientSecret.length > 0) setSecret(clientSecret);
      else tell("error");
    };
    tell("ready");
    return () => {
      delete w.stall10StartPayouts;
    };
  }, []);
  if (!secret) return <p className="muted" aria-busy="true">Opening Stripe…</p>;
  const view = new URLSearchParams(window.location.search).get("view") === "manage" ? "manage" : "setup";
  return <EmbeddedOnboarding clientSecret={secret} view={view} onExit={() => tell("exit")} />;
}
