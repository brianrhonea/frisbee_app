import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/repositories/team_history/team_history_repository.dart';
import 'package:frisbee_app/domain/models/player_profile.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/domain/models/team_history.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/profile/view_models/player_profile_viewmodel.dart';
import 'package:frisbee_app/ui/profile/view_models/team_history_viewmodel.dart';
import 'package:frisbee_app/ui/profile/widgets/profile_screen.dart';
import 'package:frisbee_app/ui/profile/widgets/team_history_section.dart';
import 'package:frisbee_app/utils/result.dart';
import 'package:provider/provider.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

class _FakeHistory implements TeamHistoryRepository {
  _FakeHistory(this.answers);

  /// One answer per call; the last repeats.
  final List<Result<List<TeamHistoryEntry>>> answers;
  var calls = 0;

  @override
  Future<Result<List<TeamHistoryEntry>>> teamHistory(String uid) async {
    final r = answers[calls.clamp(0, answers.length - 1)];
    calls++;
    return r;
  }
}

StatTotals _t(int games, int goals) => StatTotals(
  games: games,
  points: games * 4,
  goals: goals,
  assists: 2,
  blocks: 1,
);

TeamHistoryEntry _entry(
  String id, {
  bool current = true,
  bool partial = false,
  Map<String, StatTotals>? seasons,
  int? number = 17,
}) => TeamHistoryEntry(
  teamId: id,
  teamName: 'Team $id',
  kind: TeamKind.team,
  current: current,
  spot: HistorySpot(id: 's$id', name: 'Alex Smith', number: number),
  seasons: seasons ?? {'2026': _t(3, 5), '2025': _t(1, 0)},
  partial: partial,
);

Widget _host(TeamHistoryRepository repo, {bool isMe = true}) =>
    Provider<TeamHistoryRepository>.value(
      value: repo,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: TeamHistorySection(uid: 'u1', isMe: isMe),
      ),
    );

void main() {
  group('view model', () {
    test('loading, then populated', () async {
      final vm = TeamHistoryViewModel(
        uid: 'u1',
        isMe: true,
        repository: _FakeHistory([
          Result.ok([_entry('a')]),
        ]),
      );
      expect(vm.status, TeamHistoryStatus.loading);
      await pumpEventQueue();
      expect(vm.status, TeamHistoryStatus.loaded);
      expect(vm.teams, hasLength(1));
      expect(vm.isEmpty, isFalse);
      expect(vm.partial, isFalse);
      vm.dispose();
    });

    test('error, then retry loads', () async {
      final repo = _FakeHistory([
        Result.error(Exception('down')),
        Result.ok([_entry('a', partial: true)]),
      ]);
      final vm = TeamHistoryViewModel(uid: 'u1', isMe: true, repository: repo);
      await pumpEventQueue();
      expect(vm.status, TeamHistoryStatus.error);
      expect(vm.error, isNotNull);
      await vm.load();
      expect(vm.status, TeamHistoryStatus.loaded);
      expect(vm.partial, isTrue);
      expect(repo.calls, 2);
      vm.dispose();
    });

    test('empty is shown on your own profile, hidden on others', () async {
      final mine = TeamHistoryViewModel(
        uid: 'u1',
        isMe: true,
        repository: _FakeHistory([const Result.ok([])]),
      );
      final other = TeamHistoryViewModel(
        uid: 'u2',
        isMe: false,
        repository: _FakeHistory([const Result.ok([])]),
      );
      await pumpEventQueue();
      expect(mine.isEmpty, isTrue);
      expect(mine.visible, isTrue);
      expect(other.isEmpty, isTrue);
      expect(other.visible, isFalse);
      mine.dispose();
      other.dispose();
    });
  });

  group('section', () {
    testWidgets('own: current and past teams, spot, latest season', (t) async {
      final repo = _FakeHistory([
        Result.ok([_entry('a'), _entry('b', current: false)]),
      ]);
      await pumpInApp(t, _host(repo));
      expect(find.text('Team history'), findsOneWidget);
      expect(find.text('Team a'), findsOneWidget);
      expect(find.text('Team b'), findsOneWidget);
      expect(find.text('Alex Smith · #17'), findsNWidgets(2));
      // Only the current team has no "Past" pill.
      expect(find.text('Past'), findsOneWidget);
      // Latest season visible, the other behind the toggle.
      expect(
        find.textContaining('3 games · 12 points · 5 goals'),
        findsNWidgets(2),
      );
      expect(find.textContaining('1 game · 4 points'), findsNothing);
      expect(find.text('Show all seasons (2)'), findsNWidgets(2));
      await t.tap(find.text('Show all seasons (2)').first);
      await t.pumpAndSettle();
      expect(
        find.textContaining('1 game · 4 points · 0 goals'),
        findsOneWidget,
      );
      expect(find.text('Hide other seasons'), findsOneWidget);
      await t.tap(find.text('Hide other seasons'));
      await t.pumpAndSettle();
      expect(find.textContaining('1 game · 4 points'), findsNothing);
    });

    testWidgets('a team with no games says so; a lone season has no toggle', (
      t,
    ) async {
      final repo = _FakeHistory([
        Result.ok([
          _entry('a', seasons: const {}),
          _entry('b', seasons: {'2026': _t(1, 1)}, number: null),
        ]),
      ]);
      await pumpInApp(t, _host(repo));
      expect(find.text('No games tracked yet'), findsOneWidget);
      expect(find.textContaining('Show all seasons'), findsNothing);
      expect(find.text('Alex Smith'), findsOneWidget);
    });

    testWidgets('partial shows the note once', (t) async {
      final repo = _FakeHistory([
        Result.ok([_entry('a', partial: true), _entry('b', partial: true)]),
      ]);
      await pumpInApp(t, _host(repo));
      expect(find.text('Totals cover up to 1000 games'), findsOneWidget);
    });

    testWidgets('no partial, no note', (t) async {
      await pumpInApp(
        t,
        _host(
          _FakeHistory([
            Result.ok([_entry('a')]),
          ]),
        ),
      );
      expect(find.text('Totals cover up to 1000 games'), findsNothing);
    });

    testWidgets('own and empty: a short empty state', (t) async {
      await pumpInApp(t, _host(_FakeHistory([const Result.ok([])])));
      expect(find.text('Team history'), findsOneWidget);
      expect(find.textContaining('No team history yet'), findsOneWidget);
    });

    testWidgets('other and empty: the section is hidden', (t) async {
      await pumpInApp(
        t,
        _host(_FakeHistory([const Result.ok([])]), isMe: false),
      );
      expect(find.text('Team history'), findsNothing);
    });

    testWidgets('other and failed: hidden, no error', (t) async {
      await pumpInApp(
        t,
        _host(_FakeHistory([Result.error(Exception('403'))]), isMe: false),
      );
      expect(find.text('Team history'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('other with entries: shown', (t) async {
      await pumpInApp(
        t,
        _host(
          _FakeHistory([
            Result.ok([_entry('a', current: false)]),
          ]),
          isMe: false,
        ),
      );
      expect(find.text('Team history'), findsOneWidget);
      expect(find.text('Past'), findsOneWidget);
    });

    testWidgets('own and failed: an error with Retry that recovers', (t) async {
      final repo = _FakeHistory([
        Result.error(Exception('down')),
        Result.ok([_entry('a')]),
      ]);
      await pumpInApp(t, _host(repo));
      expect(find.text("Couldn't load your team history"), findsOneWidget);
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Team a'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('without the repository there is no section', (t) async {
      await pumpInApp(t, const TeamHistorySection(uid: 'u1', isMe: true));
      expect(find.text('Team history'), findsNothing);
    });

    testWidgets('large text at 200% does not overflow', (t) async {
      final repo = _FakeHistory([
        Result.ok([_entry('a', partial: true), _entry('b', current: false)]),
      ]);
      await expectNoOverflowWithLargeText(t, _host(repo));
      expect(find.text('Team history'), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines', (t) async {
      final repo = _FakeHistory([
        Result.ok([_entry('a'), _entry('b', current: false, partial: true)]),
      ]);
      await pumpInApp(t, _host(repo));
      await expectAccessible(t);
    });

    testWidgets('golden: light and dark at phone width', (t) async {
      final repo = _FakeHistory([
        Result.ok([_entry('a'), _entry('b', current: false, partial: true)]),
      ]);
      await expectGoldens(t, _host(repo), 'team_history');
    }, skip: goldenSkip != null);
  });

  group("on the profile's Teams tab", () {
    for (final (uid, isMe) in [(testUser.uid, true), ('p2', false)]) {
      testWidgets(isMe ? 'own profile shows it' : "another's shows it", (
        t,
      ) async {
        t.view.physicalSize = const Size(900, 1800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final profiles = FakeProfileRepository()
          ..put(const PlayerProfile(uid: 'p2', name: 'Pat'));
        final vm = PlayerProfileViewModel(
          uid: uid,
          profileRepository: profiles,
          authRepository: FakeAuthRepository(user: testUser),
          teamRepository: FakeTeamRepository(),
          statsRepository: FakeStatsRepository(),
          directMessageRepository: FakeDirectMessageRepository(),
        );
        addTearDown(vm.dispose);
        await t.pumpWidget(
          Provider<TeamHistoryRepository>.value(
            value: _FakeHistory([
              Result.ok([_entry('a', current: false)]),
            ]),
            child: MaterialApp(
              theme: AppTheme.light,
              home: PlayerProfileScreen(viewModel: vm),
            ),
          ),
        );
        await t.pumpAndSettle();
        // Not on the Overview tab.
        expect(find.text('Team history'), findsNothing);
        await t.tap(find.text('Teams').first);
        await t.pumpAndSettle();
        expect(find.text('Team history'), findsOneWidget);
        expect(find.text('Team a'), findsOneWidget);
        expect(find.text('Past'), findsOneWidget);
      });
    }
  });
}
