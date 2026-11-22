// "Directions" (directions.ts) against the app's directionsOptions
// (apps/mobile/lib/domain/models/directions.dart), on the vectors in
// fixtures/directions (written by
// apps/mobile/test/shared_fixtures/directions_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { directionsOptions, type SubscribePlatform } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface OptionsCase {
  name: string;
  place: string | null;
  point: [number, number] | null;
  platform: SubscribePlatform;
  options: Array<{ app: string; label: string; url: string }>;
}

describe("directions match the app (fixtures/directions/options.json)", () => {
  it.each(fixture<OptionsCase>("directions/options.json").cases)("$name", (c) => {
    const to = c.point ? { lat: c.point[0], lng: c.point[1] } : c.place!;
    expect(directionsOptions(to, c.platform)).toEqual(c.options);
  });
});
