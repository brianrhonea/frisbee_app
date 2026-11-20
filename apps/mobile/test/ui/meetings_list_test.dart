import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/app_user.dart';
import 'package:frisbee_app/domain/models/meeting.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/themes/theme.dart';
import 'package:frisbee_app/ui/meetings/view_models/meetings_list_viewmodel.dart';
import 'package:frisbee_app/ui/meetings/widgets/meetings_list_screen.dart';

import '../testing/fakes.dart';
import '../testing/meeting_fakes.dart';

const coach = AppUser(uid: 'c', displayName: 'Casey');
const player = AppUser(uid: 'p1', displayName: 'Pat');

void main() {
  late FakeTeamRepository teams;
  late FakeMeetingRepository meetings;
  final now = DateTime(2030, 1, 10, 12);

  setUp(() {
    teams = FakeTeamRepository();
    meetings = FakeMeetingRepository();
    teams.teams['t1'] = teamWith({
      'o': TeamRole.owner,
      'c': TeamRole.coach,
      'p1': TeamRole.player,
      'p2': TeamRole.player,
    });
    meetings.meetings
      ..['live'] = TeamMeeting(
        id: 'live',
        title: 'Captains sync',
        startsAt: DateTime(2030, 1, 10, 11),
        status: MeetingStatus.live,
        inviteRoles: const {TeamRole.player},
      )
      ..['soon'] = TeamMeeting(
        id: 'soon',
        title: 'Film review',
        startsAt: DateTime(2030, 1, 12, 19),
        inviteRoles: const {TeamRole.player},
      )
      ..['later'] = TeamMeeting(
        id: 'later',
        title: 'Hat recap',
        startsAt: DateTime(2030, 1, 20, 19),
        inviteRoles: const {TeamRole.player},
        rsvps: const {'p1': MeetingRsvp.attending},
      )
      // Earlier today but not started: still upcoming, as on the website.
      ..['today'] = TeamMeeting(
        id: 'today',
        title: 'Morning check-in',
        startsAt: DateTime(2030, 1, 10, 8),
        inviteRoles: const {TeamRole.player},
      )
      ..['old'] = TeamMeeting(
        id: 'old',
        title: 'Zone film',
        startsAt: DateTime(2030, 1, 3, 19),
        inviteRoles: const {TeamRole.player},
      )
      ..['done'] = TeamMeeting(
        id: 'done',
        title: 'Lines',
        startsAt: DateTime(2030, 1, 5, 19),
        status: MeetingStatus.ended,
        inviteRoles: const {TeamRole.player},
      )
      // Admins only: a player doesn't see it.
      ..['admins'] = TeamMeeting(
        id: 'admins',
        title: 'Captains and coach',
        startsAt: DateTime(2030, 1, 15, 20),
      );
  });

  MeetingsListViewModel list(AppUser user) => MeetingsListViewModel(
    teamId: 't1',
    meetingRepository: meetings,
    teamRepository: teams,
    authRepository: FakeAuthRepository(user: user),
    clock: () => now,
  );

  group('MeetingsListViewModel', () {
    test(
      'live first, then upcoming soonest first, past newest first',
      () async {
        final vm = list(player);
        addTearDown(vm.dispose);
        await pumpEventQueue();
        expect(vm.loaded, isTrue);
        expect(vm.live.map((m) => m.id), ['live']);
        expect(vm.upcoming.map((m) => m.id), ['today', 'soon', 'later']);
        expect(vm.past.map((m) => m.id), ['done', 'old']);
        expect(vm.canCreate, isFalse);
      },
    );

    test('Needs RSVP while unanswered and ahead', () async {
      final vm = list(player);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      final byId = {
        for (final m in [...vm.upcoming, ...vm.past]) m.id: m,
      };
      expect(vm.needsRsvp(byId['soon']!), isTrue);
      expect(vm.needsRsvp(byId['later']!), isFalse);
      expect(vm.needsRsvp(byId['done']!), isFalse);
      expect(vm.needsRsvp(byId['old']!), isFalse);
      expect(vm.myRsvp(byId['later']!), MeetingRsvp.attending);
    });

    test('admins see every meeting and can schedule', () async {
      final vm = list(coach);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.canCreate, isTrue);
      expect(vm.upcoming.map((m) => m.id), contains('admins'));
    });

    test('follows the Meetings section switch', () async {
      teams.teams['t1'] = teams.teams['t1']!.copyWith(
        sectionsOff: {OptionalSection.meetings},
      );
      final vm = list(player);
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.meetingsOn, isFalse);
    });
  });

  group('MeetingsListScreen', () {
    Future<void> pump(WidgetTester tester, MeetingsListViewModel vm) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MeetingsListScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows live, upcoming with answers, and past on request', (
      tester,
    ) async {
      final vm = list(player);
      addTearDown(vm.dispose);
      await pump(tester, vm);
      expect(find.text('LIVE NOW'), findsOneWidget);
      expect(find.text('Captains sync'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Film review'), findsOneWidget);
      // Only the unanswered one still ahead (this morning's has passed);
      // the answered one shows its answer.
      expect(find.text('Needs RSVP'), findsOneWidget);
      expect(find.text('Going'), findsOneWidget);
      expect(find.text('Zone film'), findsNothing);
      expect(find.text('New meeting'), findsNothing);
      // Admins-only meetings stay hidden from players.
      expect(find.text('Captains and coach'), findsNothing);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();
      expect(find.text('Zone film'), findsOneWidget);
      expect(find.text('Lines'), findsOneWidget);
      expect(find.text('Captains sync'), findsNothing);
      expect(find.text('Needs RSVP'), findsNothing);
    });

    testWidgets('admins get New meeting; Meetings off says so', (tester) async {
      final vm = list(coach);
      addTearDown(vm.dispose);
      await pump(tester, vm);
      expect(find.text('New meeting'), findsOneWidget);

      teams.teams['t1'] = teams.teams['t1']!.copyWith(
        sectionsOff: {OptionalSection.meetings},
      );
      final off = list(coach);
      addTearDown(off.dispose);
      await pump(tester, off);
      expect(find.text('Meetings are off'), findsOneWidget);
      expect(find.text('New meeting'), findsNothing);
    });
  });
}
