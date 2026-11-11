import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/group_tournament.dart';
import 'package:frisbee_app/domain/models/hosted_tournament.dart';
import 'package:frisbee_app/domain/tournament_engine/team_builder.dart';

void main() {
  List<TournamentTeam> teams(int n) => blankTeams(n);

  List<DraftPlayer> players(
    int n, {
    int seed = 1,
    bool genders = false,
    bool someUnknown = false,
  }) {
    final random = Random(seed);
    return [
      for (var i = 0; i < n; i++)
        (
          uid: 'u$i',
          name: 'Player $i',
          skill: 1 + random.nextInt(5),
          gender: !genders || (someUnknown && i % 7 == 0)
              ? null
              : (random.nextBool() ? GenderMatch.mmp : GenderMatch.wmp),
        ),
    ];
  }

  int skillOf(List<DraftPlayer> all, TournamentTeam t) => t.playerIds
      .map((id) => all.firstWhere((p) => p.uid == id).skill)
      .fold(0, (a, b) => a + b);

  int spread(Iterable<int> values) => values.reduce(max) - values.reduce(min);

  test(
    'everyone lands on exactly one team and sizes differ by at most one',
    () {
      for (final n in [1, 5, 8, 17, 23, 40]) {
        for (final count in [2, 3, 4, 6]) {
          final all = players(n, seed: n * count);
          final result = balancedDraft(all, teams(count), seed: 7);
          final placed = [for (final t in result) ...t.playerIds];
          expect(placed.toSet(), {
            for (final p in all) p.uid,
          }, reason: '$n/$count');
          expect(placed, hasLength(n), reason: '$n/$count');
          expect(
            spread(result.map((t) => t.playerIds.length)),
            lessThanOrEqualTo(1),
            reason: '$n players, $count teams',
          );
        }
      }
    },
  );

  test('total skill stays within the best player of even', () {
    for (var seed = 0; seed < 40; seed++) {
      final all = players(24 + seed % 9, seed: seed);
      final count = 2 + seed % 5;
      final result = balancedDraft(all, teams(count), seed: seed);
      expect(
        spread(result.map((t) => skillOf(all, t))),
        lessThanOrEqualTo(5),
        reason: 'seed $seed',
      );
    }
  });

  test('the strongest players are spread across the teams', () {
    final all = [
      for (var i = 0; i < 4; i++)
        (uid: 'star$i', name: 'Star $i', skill: 5, gender: null),
      for (var i = 0; i < 8; i++)
        (uid: 'new$i', name: 'New $i', skill: 1, gender: null),
    ];
    final result = balancedDraft(all, teams(4), seed: 3);
    for (final t in result) {
      expect(t.playerIds.where((id) => id.startsWith('star')), hasLength(1));
    }
  });

  test('the same seed gives the same teams', () {
    final all = players(30);
    List<List<String>> rosters(int seed) => [
      for (final t in balancedDraft(all, teams(4), seed: seed)) t.playerIds,
    ];
    expect(rosters(5), rosters(5));
  });

  test('a seed only breaks ties; a different one can reshuffle equals', () {
    final all = [
      for (var i = 0; i < 12; i++)
        (uid: 'u$i', name: 'P$i', skill: 3, gender: null),
    ];
    final a = balancedDraft(all, teams(3), seed: 1);
    final differs =
        [
          for (var seed = 2; seed < 12; seed++)
            balancedDraft(all, teams(3), seed: seed),
        ].any(
          (b) =>
              [for (final t in b) t.playerIds].toString() !=
              [for (final t in a) t.playerIds].toString(),
        );
    expect(differs, isTrue);
  });

  test('duplicate signups count once', () {
    final one = (uid: 'u1', name: 'Pat', skill: 4, gender: null);
    final result = balancedDraft([one, one, one], teams(2), seed: 1);
    expect([for (final t in result) ...t.playerIds], ['u1']);
  });

  test(
    'each team keeps its id and name, and the captain is its best player',
    () {
      final all = players(20);
      final start = teams(4);
      final result = balancedDraft(all, start, seed: 9);
      for (var i = 0; i < 4; i++) {
        final t = result[i];
        expect(t.id, start[i].id);
        expect(t.name, start[i].name);
        final best = t.playerIds
            .map((id) => all.firstWhere((p) => p.uid == id).skill)
            .reduce(max);
        final captain = all.firstWhere((p) => p.uid == t.captainId);
        expect(captain.skill, best);
        expect(t.playerIds, contains(t.captainId));
        expect(t.playerNames.keys.toSet(), t.playerIds.toSet());
      }
    },
  );

  test('replaces rosters that were already there', () {
    final stale = [
      const TournamentTeam(id: 'team1', name: 'Red', playerIds: ['old']),
    ];
    final result = balancedDraft(players(3), stale, seed: 1);
    expect(result.single.playerIds, isNot(contains('old')));
    expect(result.single.playerIds, hasLength(3));
  });

  test('no teams or no players is fine', () {
    expect(balancedDraft(players(5), const [], seed: 1), isEmpty);
    final empty = balancedDraft(const [], teams(2), seed: 1);
    expect(empty.map((t) => t.playerIds), [isEmpty, isEmpty]);
    expect(empty.map((t) => t.captainId), [null, null]);
  });

  group('mixed', () {
    test('each gender match is split evenly and teams stay even', () {
      for (var seed = 0; seed < 40; seed++) {
        final all = players(
          20 + seed % 15,
          seed: seed,
          genders: true,
          someUnknown: seed.isOdd,
        );
        final count = 2 + seed % 4;
        final result = balancedDraft(
          all,
          teams(count),
          seed: seed,
          mixed: true,
        );
        for (final g in [GenderMatch.mmp, GenderMatch.wmp]) {
          final counts = [
            for (final t in result)
              t.playerIds
                  .where((id) => all.firstWhere((p) => p.uid == id).gender == g)
                  .length,
          ];
          expect(spread(counts), lessThanOrEqualTo(1), reason: '$g seed $seed');
        }
        expect(
          spread(result.map((t) => t.playerIds.length)),
          lessThanOrEqualTo(1),
          reason: 'sizes, seed $seed',
        );
        expect(
          {for (final t in result) ...t.playerIds},
          hasLength(all.length),
        );
      }
    });

    test('players without a gender match are still placed', () {
      final all = [
        (uid: 'a', name: 'A', skill: 3, gender: GenderMatch.mmp),
        (uid: 'b', name: 'B', skill: 3, gender: GenderMatch.wmp),
        (uid: 'c', name: 'C', skill: 3, gender: null),
        (uid: 'd', name: 'D', skill: 3, gender: null),
      ];
      final result = balancedDraft(all, teams(2), seed: 1, mixed: true);
      expect(result.map((t) => t.playerIds.length), [2, 2]);
    });

    test('mixed off ignores gender', () {
      final all = players(12, genders: true);
      final result = balancedDraft(all, teams(3), seed: 2);
      expect(result.map((t) => t.playerIds.length), [4, 4, 4]);
    });
  });
}
