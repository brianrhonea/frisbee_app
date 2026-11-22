// "Directions" to an event's place: the maps apps to choose from. Each is
// a web link the app opens when it's installed (universal / app links) and
// the browser otherwise, so nothing needs to know what's installed. The
// app's directionsOptions (apps/mobile/lib/domain/models/directions.dart)
// matches; both are checked against fixtures/directions.
import type { SubscribePlatform } from "./calendar.js";

export type MapsApp = "apple" | "google" | "waze";

export interface DirectionsOption {
  app: MapsApp;
  label: string;
  url: string;
}

/** Where to go: an address or place name, or a point. */
export type Destination = string | { lat: number; lng: number };

/**
 * The maps apps for directions to [to], best first for [platform]: Apple
 * Maps only on Apple devices (first there), then Google Maps and Waze.
 */
export function directionsOptions(to: Destination, platform: SubscribePlatform): DirectionsOption[] {
  const enc = encodeURIComponent;
  const point = typeof to === "string" ? null : `${to.lat},${to.lng}`;
  const q = enc(point ?? (to as string).trim());
  const all: Record<MapsApp, DirectionsOption> = {
    apple: { app: "apple", label: "Apple Maps", url: `https://maps.apple.com/?daddr=${q}` },
    google: { app: "google", label: "Google Maps", url: `https://www.google.com/maps/dir/?api=1&destination=${q}` },
    waze: { app: "waze", label: "Waze", url: point ? `https://waze.com/ul?ll=${q}&navigate=yes` : `https://waze.com/ul?q=${q}&navigate=yes` },
  };
  const order: MapsApp[] = platform === "ios" || platform === "macos" ? ["apple", "google", "waze"] : ["google", "waze"];
  return order.map((a) => all[a]);
}
