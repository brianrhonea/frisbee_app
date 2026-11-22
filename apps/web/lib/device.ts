import type { SubscribePlatform } from "@stall10/shared";

/**
 * The device, for which apps to offer first (subscribe options,
 * directions): browsers can't see what's installed.
 */
export function devicePlatform(): SubscribePlatform {
  const ua = typeof navigator === "undefined" ? "" : navigator.userAgent;
  if (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return "ios";
  if (/Macintosh/.test(ua)) return "macos";
  if (/Android/.test(ua)) return "android";
  return "other";
}
