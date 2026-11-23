// Who can enter a hosted event (entryChoices in tournaments.ts) against the
// app's EntryChoice (apps/mobile/lib/domain/models/hosted_tournament.dart),
// on fixtures/entry_choices (written by
// apps/mobile/test/shared_fixtures/entry_choice_fixtures_test.dart).
import { describe, expect, it } from "vitest";
import { entryChoiceLabels, entryChoiceOf, entryChoicesFor, entryFields, type EntryChoice, type HostedKind, type TournamentEntryType } from "../src/index.js";
import { fixture } from "./shared_fixtures.js";

type Case =
  | { kind: HostedKind; entryType: TournamentEntryType; teamEntry: boolean; choice: EntryChoice }
  | { kind: HostedKind; offers: EntryChoice[] }
  | { choice: EntryChoice; label: string; stores: { entryType: TournamentEntryType; teamEntry: boolean } };

describe("entry choices match the app (fixtures/entry_choices/choices.json)", () => {
  const cases = fixture<Case>("entry_choices/choices.json").cases;
  it("reads the same choice from an event's fields", () => {
    for (const c of cases) if ("entryType" in c) expect(entryChoiceOf(c)).toBe(c.choice);
  });
  it("offers the same choices per kind", () => {
    for (const c of cases) if ("offers" in c) expect([...entryChoicesFor(c.kind)]).toEqual(c.offers);
  });
  it("labels and stores each choice the same way", () => {
    for (const c of cases) {
      if (!("stores" in c)) continue;
      expect(entryChoiceLabels[c.choice]).toBe(c.label);
      expect(entryFields(c.choice)).toEqual(c.stores);
    }
  });
});
