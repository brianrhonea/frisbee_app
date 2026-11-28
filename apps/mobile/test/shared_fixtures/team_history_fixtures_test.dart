// Checks the app's per-spot season totals (PlayerProfileViewModel._recompute,
// read through ProfileSummary.teamSeasons) against the shared vectors in
// packages/shared/fixtures/team_history/totals.json, which the API's
// seasonTotalsFor is checked against too. The fixture is derived by hand
// from this code, so this test only reads it; it never rewrites it (no
// UPDATE_FIXTURES here).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/roster_player.dart';
import 'package:frisbee_app/domain/models/stats.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';

import '../testing/fakes.dart';

Map<String, Object?> _asMap(StatTotals t) => {
  'games': t.games,
  'points': t.points,
  'goals': t.goals,
  'assists': t.assists,
  'blocks': t.blocks,
  'completions': t.completions,
  'throwaways': t.throwaways,
  'catches': t.catches,
  'drops': t.drops,
};

void main() {
  final doc =
      jsonDecode(
            File(
              '../../packages/shared/fixtures/team_history/totals.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final games = [
    for (final g in doc['games'] as List)
      StatsGame.fromMap(
        (g as Map)['id'] as String,
        Map<String, dynamic>.from(g),
      ),
  ];

  for (final c in doc['cases'] as List) {
    final name = (c as Map)['name'] as String;
    test(name.split(':').first, () async {
      final spot = c['spot'] as String;
      final auth = FakeAuthRepository(user: testUser);
      final teams = FakeTeamRepository();
      teams.teams['t1'] = teamWith({
        'owner': TeamRole.owner,
        testUser.uid: TeamRole.player,
      });
      teams.roster['t1'] = [
        RosterPlayer(id: spot, name: 'Spot', userId: testUser.uid),
      ];
      final stats = FakeStatsRepository()..games['t1'] = games;
      final vm = PlayerProfileViewModel(
        uid: testUser.uid,
        profileRepository: FakeProfileRepository(),
        authRepository: auth,
        teamRepository: teams,
        statsRepository: stats,
        directMessageRepository: FakeDirectMessageRepository(),
      );
      await pumpEventQueue();
      final got = vm.summary.teamSeasons['t1'] ?? const {};
      final want = (c['seasons'] as Map).cast<String, dynamic>();
      expect(got.keys.toSet(), want.keys.toSet());
      for (final year in want.keys) {
        expect(
          _asMap(got[year]!),
          Map<String, Object?>.from(want[year] as Map),
          reason: '$name: season $year',
        );
      }
      vm.dispose();
    });
  }

  // A date outside 1900-2100 (UTC) counts toward no season, as on the API.
  test('season years are bounded to 1900-2100', () async {
    final base = Map<String, dynamic>.from((doc['games'] as List)[1] as Map);
    final spotCase = (doc['cases'] as List).cast<Map>().firstWhere(
      (c) => (c['seasons'] as Map).isNotEmpty,
    );
    final spot = spotCase['spot'] as String;
    final dates = {
      '1899-12-31T23:59:59Z': false,
      '1900-01-01T00:00:00Z': true,
      '2100-12-31T23:59:59Z': true,
      '2101-01-01T00:00:00Z': false,
      '0001-06-01T00:00:00Z': false,
    };
    for (final e in dates.entries) {
      final teams = FakeTeamRepository();
      teams.teams['t1'] = teamWith({
        'owner': TeamRole.owner,
        testUser.uid: TeamRole.player,
      });
      teams.roster['t1'] = [
        RosterPlayer(id: spot, name: 'Spot', userId: testUser.uid),
      ];
      final stats = FakeStatsRepository()
        ..games['t1'] = [
          StatsGame.fromMap('g', {...base, 'date': e.key}),
        ];
      final vm = PlayerProfileViewModel(
        uid: testUser.uid,
        profileRepository: FakeProfileRepository(),
        authRepository: FakeAuthRepository(user: testUser),
        teamRepository: teams,
        statsRepository: stats,
        directMessageRepository: FakeDirectMessageRepository(),
      );
      await pumpEventQueue();
      final seasons = vm.summary.teamSeasons['t1'] ?? const {};
      expect(
        seasons.keys.toList(),
        e.value ? [e.key.substring(0, 4)] : isEmpty,
        reason: e.key,
      );
      expect(vm.summary.games, e.value ? isNotEmpty : isEmpty, reason: e.key);
      vm.dispose();
    }
  });
}
