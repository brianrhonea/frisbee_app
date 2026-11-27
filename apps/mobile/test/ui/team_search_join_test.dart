// Sprint 4 (B3): a Join button on team search results, only where the team
// page's own join path applies. Parity: website team search.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/explore/view_models/player_search_viewmodel.dart';
import 'package:frisbee_app/ui/explore/widgets/explore_screen.dart';
import 'package:frisbee_app/ui/teams/view_models/team_search_viewmodel.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';
import '../ui_harness/harness.dart';

/// Refuses a request the way the API's club age rule does.
class _ClubTeams extends FakeTeamRepository {
  @override
  Future<Result<void>> requestToJoin(String teamId, AppUser user) async =>
      Result.error(
        const ApiException(
          'failed_precondition',
          'Club teams are for players 16 and over.',
        ),
      );
}

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  TeamListing listing(
    String id,
    String name, {
    TeamKind kind = TeamKind.team,
    bool approval = false,
    bool requests = false,
  }) => TeamListing(
    id: id,
    name: name,
    division: Division.mixed,
    level: CompetitionLevel.club,
    kind: kind,
    requiresApproval: approval,
    allowJoinRequests: requests,
  );

  Team teamFor(TeamListing l, {String owner = 'owner'}) => Team(
    id: l.id,
    name: l.name,
    division: l.division,
    level: l.level,
    ownerId: owner,
    members: {owner: TeamRole.owner},
    memberNames: {owner: 'Owner'},
    kind: l.kind,
    requiresApproval: l.requiresApproval,
  );

  void seed(FakeTeamRepository repo, List<TeamListing> all) {
    for (final l in all) {
      repo.listings[l.id] = l;
      repo.teams[l.id] = teamFor(l);
    }
  }

  setUp(() {
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(user: testUser);
    seed(teams, [
      listing('open', 'Open Team Pickup', kind: TeamKind.community),
      listing(
        'appr',
        'Approval Team Pickup',
        kind: TeamKind.community,
        approval: true,
      ),
      listing('req', 'Requests Team', requests: true),
      listing('code', 'Code Team'),
    ]);
  });

  Future<TeamSearchViewModel> pump(
    WidgetTester tester, {
    FakeTeamRepository? repo,
    FakeAuthRepository? as,
    GoldenTheme theme = GoldenTheme.light,
  }) async {
    final vm = TeamSearchViewModel(
      teamRepository: repo ?? teams,
      authRepository: as ?? auth,
    );
    final players = PlayerSearchViewModel(
      profileRepository: FakeProfileRepository(),
    );
    addTearDown(vm.dispose);
    addTearDown(players.dispose);
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme == GoldenTheme.dark ? AppTheme.dark : AppTheme.light,
        home: ExploreScreen(viewModel: vm, players: players),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'team');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    return vm;
  }

  Finder joinIn(String name) => find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(InkWell)),
    matching: find.byType(FilledButton),
  );

  test('which results can be joined, as the team page decides', () async {
    final vm = TeamSearchViewModel(teamRepository: teams, authRepository: auth);
    addTearDown(vm.dispose);
    final open = listing('o', 'o', kind: TeamKind.community);
    expect(vm.canJoin(open), isTrue);
    expect(vm.joinLabel(open), 'Join');
    final approval = listing(
      'a',
      'a',
      kind: TeamKind.community,
      approval: true,
    );
    expect(vm.canJoin(approval), isTrue);
    expect(vm.joinLabel(approval), 'Ask to join');
    expect(vm.canJoin(listing('r', 'r', requests: true)), isTrue);
    // Joins by invite code only.
    expect(vm.canJoin(listing('c', 'c')), isFalse);
  });

  testWidgets(
    'open groups join, approval ones ask, code-only teams have no button',
    (tester) async {
      final vm = await pump(tester);
      expect(find.text('Open Team Pickup'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Ask to join'), findsNWidgets(2));
      // The code-only team shows no Join, only its chevron.
      expect(joinIn('Code Team'), findsNothing);
      expect(find.text('Code Team'), findsOneWidget);

      // Open group: joining makes the user a member.
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(teams.teams['open']!.members.containsKey(testUser.uid), isTrue);
      expect(vm.isMine('open'), isTrue);
      expect(find.text('Your community'), findsOneWidget);

      // Approval group: a request is sent and the row says so.
      await tester.tap(joinIn('Approval Team Pickup'));
      await tester.pumpAndSettle();
      expect(teams.joinRequests['appr']!.single.uid, testUser.uid);
      expect(find.text('Requested'), findsOneWidget);
    },
  );

  testWidgets("a team you're on shows no Join", (tester) async {
    teams.teams['req'] = teams.teams['req']!.copyWith(
      members: {'owner': TeamRole.owner, testUser.uid: TeamRole.player},
    );
    await pump(tester);
    expect(find.text('Your team'), findsOneWidget);
    expect(joinIn('Requests Team'), findsNothing);
  });

  testWidgets("the server's refusal is shown, e.g. the club age rule", (
    tester,
  ) async {
    final club = _ClubTeams();
    seed(club, [listing('req', 'Requests Team', requests: true)]);
    await pump(tester, repo: club);
    await tester.tap(find.text('Ask to join'));
    await tester.pumpAndSettle();
    expect(
      find.text('Club teams are for players 16 and over.'),
      findsOneWidget,
    );
    expect(find.text('Requested'), findsNothing);
  });

  testWidgets('a signed-out visitor sees no Join', (tester) async {
    await pump(tester, as: FakeAuthRepository());
    expect(find.text('Join'), findsNothing);
    expect(find.text('Ask to join'), findsNothing);
  });

  for (final theme in GoldenTheme.values) {
    testWidgets('results with Join meet guidelines, ${theme.name}', (
      tester,
    ) async {
      await pump(tester, theme: theme);
      await expectAccessible(tester);
    });
  }
}
