// The app's "Add to calendar" files (apps/mobile/lib/utils/ics.dart)
// against ical.ts, on the vectors in fixtures/ics (written by
// apps/mobile/test/shared_fixtures/ics_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { icsDate, icsEvent, icsFileName, icsFold, icsText } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

interface EventCase {
  name: string;
  uid: string;
  title: string;
  startsAt: string;
  endsAt?: string;
  location?: string;
  description?: string;
  now: string;
  ics: string;
  fileName: string;
}

describe("add to calendar files match the app (fixtures/ics/events.json)", () => {
  it.each(fixture<EventCase>("ics/events.json").cases)("$name", (c) => {
    const { now, ics, fileName, name: _name, ...event } = c;
    expect(icsEvent(event, now)).toBe(ics);
    expect(icsFileName(c.title)).toBe(fileName);
  });
});

describe("iCalendar pieces match the app (fixtures/ics/pieces.json)", () => {
  const f = { text: icsText, date: icsDate, fold: icsFold, fileName: icsFileName } as const;
  it.each(fixture<{ kind: keyof typeof f; input: string; output: string }>("ics/pieces.json").cases)("$kind: $input", (c) => {
    expect(f[c.kind](c.input)).toBe(c.output);
  });
});
