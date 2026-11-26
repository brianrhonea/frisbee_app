// Club teams are for players 16 and over (docs/product-spec.md): the app
// says so up front and shows the API's refusal where joining fails. The
// API does the checking (apps/api/src/teams/club_age.ts); these mirror
// apps/web's club-age tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:frisbee_app/data/services/api_client.dart';
import 'package:frisbee_app/domain/models/personal_details.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/core/ui/error_message.dart';
import 'package:frisbee_app/ui/teams/view_models/join_link_viewmodel.dart';
import 'package:frisbee_app/ui/teams/view_models/teams_viewmodel.dart';
import 'package:frisbee_app/ui/teams/widgets/join_link_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/team_form.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:frisbee_app/utils/result.dart';

import '../testing/fakes.dart';

void main() {
  late FakeTeamRepository teams;
  late FakeAuthRepository auth;

  setUp(() {
    teams = FakeTeamRepository();
    auth = FakeAuthRepository(user: testUser);
  });

  Team club({CompetitionLevel level = CompetitionLevel.club}) => Team(
    id: 't1',
    name: 'Haze',
    division: Division.open,
    level: level,
    ownerId: 'owner',
    members: const {'owner': TeamRole.owner},
  );

  const tooYoung = ApiException('failed_precondition', clubTooYoungMessage);
  const noBirthDate = ApiException(
    'failed_precondition',
    clubNeedsBirthDateMessage,
  );

  test('the wording matches the API and the website', () {
    expect(clubTooYoungMessage, 'Club teams are for players 16 and over.');
    expect(
      clubNeedsBirthDateMessage,
      'Add your date of birth in About you to join a club team.',
    );
    expect(
      clubCantJoinMessage('Sam'),
      "Sam can't join a club team: club teams are for players 16 and over.",
    );
    // Shown as the API words it.
    expect(errorMessage(Result<void>.error(tooYoung)), clubTooYoungMessage);
    expect(errorMessage(noBirthDate), clubNeedsBirthDateMessage);
  });

  test('club teams are teams at the club level only', () {
    expect(club().isClubTeam, isTrue);
    expect(TeamListing.of(club()).isClubTeam, isTrue);
    for (final level in CompetitionLevel.values) {
      if (level == CompetitionLevel.club) continue;
      expect(club(level: level).isClubTeam, isFalse);
    }
    final group = Team(
      id: 'g1',
      name: 'Pickup',
      division: Division.mixed,
      level: CompetitionLevel.club,
      ownerId: 'owner',
      members: const {'owner': TeamRole.owner},
      kind: TeamKind.community,
    );
    expect(group.isClubTeam, isFalse);
  });

  group('invite links', () {
    JoinLinkViewModel linkVm() => JoinLinkViewModel(
      code: 'CODEt1',
      teamRepository: teams,
      authRepository: auth,
    );

    test('say a club team is 16 and over, and pass on a refusal', () async {
      teams.teams['t1'] = club();
      teams.listings['t1'] = TeamListing.of(club());
      teams.joinError = tooYoung;
      final vm = linkVm();
      await pumpEventQueue();
      expect(vm.isClubTeam, isTrue);
      await vm.join.execute();
      expect(errorMessage(vm.join.result), clubTooYoungMessage);
      vm.dispose();

      teams.listings['t1'] = TeamListing.of(
        club(level: CompetitionLevel.youth),
      );
      final youth = linkVm();
      await pumpEventQueue();
      expect(youth.isClubTeam, isFalse);
      youth.dispose();
    });

    testWidgets('the link screen shows the rule and the refusal', (
      tester,
    ) async {
      teams.teams['t1'] = club();
      teams.listings['t1'] = TeamListing.of(club());
      teams.joinError = noBirthDate;
      final vm = linkVm();
      addTearDown(vm.dispose);
      final router = GoRouter(
        initialLocation: '/join/CODEt1',
        routes: [
          GoRoute(
            path: '/join/:code',
            builder: (_, _) => JoinLinkScreen(viewModel: vm),
          ),
          GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
      await tester.pumpAndSettle();
      expect(find.text(clubTooYoungMessage), findsOneWidget);
      await tester.tap(find.text('Join Haze'));
      await tester.pumpAndSettle();
      expect(find.text(clubNeedsBirthDateMessage), findsOneWidget);
    });
  });

  group('invites', () {
    TeamInvite invite() => const TeamInvite(
      teamId: 't1',
      teamName: 'Haze',
      invitedByName: 'Olive',
    );

    test('a club team invite says so; accepting passes on a refusal', () async {
      teams.teams['t1'] = club();
      teams.listings['t1'] = TeamListing.of(club());
      teams.invites[testUser.uid] = [invite()];
      teams.joinError = tooYoung;
      final vm = TeamsViewModel(teamRepository: teams, authRepository: auth);
      await pumpEventQueue();
      expect(vm.isClubInvite(vm.invites.single), isTrue);
      await vm.acceptInvite.execute(vm.invites.single);
      expect(errorMessage(vm.acceptInvite.result), clubTooYoungMessage);
      expect(teams.teams['t1']!.roleOf(testUser.uid), isNull);
      vm.dispose();
    });

    test('other levels say nothing', () async {
      teams.teams['t1'] = club(level: CompetitionLevel.college);
      teams.listings['t1'] = TeamListing.of(
        club(level: CompetitionLevel.college),
      );
      teams.invites[testUser.uid] = [invite()];
      final vm = TeamsViewModel(teamRepository: teams, authRepository: auth);
      await pumpEventQueue();
      expect(vm.isClubInvite(vm.invites.single), isFalse);
      vm.dispose();
    });

    testWidgets('the Teams tab shows the rule on the invite and the refusal', (
      tester,
    ) async {
      teams.teams['t1'] = club();
      teams.listings['t1'] = TeamListing.of(club());
      teams.invites[testUser.uid] = [invite()];
      teams.joinError = tooYoung;
      final vm = TeamsViewModel(teamRepository: teams, authRepository: auth);
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TeamsScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(clubTooYoungMessage), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      // The rule on the invite, and the refusal in a snack bar.
      expect(find.text(clubTooYoungMessage), findsNWidgets(2));
    });
  });

  group('the team form', () {
    Future<void> pump(WidgetTester tester, {NewTeam? initial}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: TeamForm(
                  initial: initial,
                  submitLabel: initial == null ? 'Create team' : 'Save',
                  onSubmit: (_) {},
                ),
              ),
            ),
          ),
        );

    testWidgets('says club teams are for players 16 and over', (tester) async {
      await pump(tester);
      expect(find.text(clubTooYoungMessage), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<CompetitionLevel>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('College').last);
      await tester.pumpAndSettle();
      expect(find.text(clubTooYoungMessage), findsNothing);
    });

    testWidgets('moving a team to club says everyone on it must be 16+', (tester) async {
      await pump(
        tester,
        initial: const NewTeam(
          name: 'Haze',
          division: Division.open,
          level: CompetitionLevel.youth,
        ),
      );
      expect(find.textContaining(clubTooYoungMessage), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<CompetitionLevel>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Club').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          '$clubTooYoungMessage Switching an existing team to club needs '
          'everyone on it to be 16 or over with a date of birth.',
        ),
        findsOneWidget,
      );
    });
  });
}
