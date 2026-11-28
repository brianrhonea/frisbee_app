// Sprint 5, R1 (app): before/after pictures of the profile's Teams tab with
// Team history, on fake data. Skipped unless asked for:
//   flutter test test/screenshots/r1_app_test.dart \
//     --dart-define=SCREENSHOTS=<review/app/R1-team-history dir> \
//     --dart-define=SHOT_WIDTH=390|1024 [--dart-define=SHOT_THEME=dark]
// Writes teams_<width>_<theme>_before.png (no history) and _after.png.
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team_history/team_history_repository.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_history.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import 's4_common.dart';
import 'shot_env.dart';

class _History implements TeamHistoryRepository {
  @override
  Future<Result<List<TeamHistoryEntry>>> teamHistory(String uid) async {
    StatTotals t(int g, int goals) => StatTotals(
      games: g,
      points: g * 5,
      goals: goals,
      assists: g,
      blocks: 2,
    );
    TeamHistoryEntry e(
      String id,
      String name,
      bool current,
      Map<String, StatTotals> seasons, {
      bool partial = false,
    }) => TeamHistoryEntry(
      teamId: id,
      teamName: name,
      kind: TeamKind.team,
      current: current,
      spot: const HistorySpot(id: 's', name: 'Test User', number: 17),
      seasons: seasons,
      partial: partial,
    );
    return Result.ok([
      e('a', 'Northside Flyers', true, {'2026': t(12, 18), '2025': t(9, 11)}),
      e('b', 'Mile High Club', false, {'2024': t(14, 20)}, partial: true),
    ]);
  }
}

void main() {
  final skip = s4Out.isEmpty ? 'pass --dart-define=SCREENSHOTS=<dir>' : null;
  for (final phase in ['before', 'after']) {
    testWidgets('teams tab $phase', skip: skip != null, (tester) async {
      await shotSize(tester);
      final auth = FakeAuthRepository(user: testUser);
      final vm = PlayerProfileViewModel(
        uid: testUser.uid,
        profileRepository: FakeProfileRepository(),
        authRepository: auth,
        teamRepository: FakeTeamRepository(),
        statsRepository: FakeStatsRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
      );
      addTearDown(vm.dispose);
      await shotPump(
        tester,
        PlayerProfileScreen(viewModel: vm),
        wrap: (app) => phase == 'after'
            ? Provider<TeamHistoryRepository>.value(
                value: _History(),
                child: app,
              )
            : app,
      );
      await tester.tap(find.text('Teams').last);
      await shotCapture(
        tester,
        'teams_${shotWidth}_${s4Dark ? 'dark' : 'light'}_$phase',
      );
    });
  }
}
