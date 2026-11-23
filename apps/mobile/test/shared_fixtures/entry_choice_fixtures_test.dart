// Who can enter a hosted event (EntryChoice in hosted_tournament.dart),
// checked by packages/shared/test/entry_choice_fixtures.test.ts against
// entryChoices in tournaments.ts. See fixture_file.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';

import 'fixture_file.dart';

void main() {
  test('entry choices (entry_choices/choices.json)', () {
    final cases = [
      for (final kind in HostedKind.values)
        for (final type in TournamentEntryType.values)
          for (final teamEntry in [false, true])
            {
              'kind': kind.name,
              'entryType': type.name,
              'teamEntry': teamEntry,
              'choice': EntryChoice.of(kind, type, teamEntry).name,
            },
    ];
    checkFixture(
      'entry_choices/choices.json',
      'Who can enter: the choice an event\'s kind, entryType and teamEntry '
          'make, the choices each kind offers, their labels and the fields '
          'each choice stores.',
      [
        ...cases,
        for (final kind in HostedKind.values)
          {
            'kind': kind.name,
            'offers': [for (final c in EntryChoice.forKind(kind)) c.name],
          },
        for (final c in EntryChoice.values)
          {
            'choice': c.name,
            'label': c.label,
            'stores': {'entryType': c.entryType.name, 'teamEntry': c.teamEntry},
          },
      ],
    );
  });

  test('a league offers teams and players; a tournament keeps its switch', () {
    expect(EntryChoice.forKind(HostedKind.league), contains(EntryChoice.both));
    expect(
      EntryChoice.forKind(HostedKind.tournament),
      isNot(contains(EntryChoice.both)),
    );
    expect(
      EntryChoice.of(HostedKind.tournament, TournamentEntryType.players, true),
      EntryChoice.players,
    );
  });
}
