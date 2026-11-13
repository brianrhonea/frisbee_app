import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/notification.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';
import 'package:frisbee_app/ui/shell/view_models/shell_viewmodel.dart';
import 'package:frisbee_app/ui/shell/widgets/app_shell.dart';

import '../testing/fakes.dart';

void main() {
  test('breadcrumbs start at the section and link back up', () {
    String? name(String id) => id == 't1' ? 'Cascades' : null;
    List<String> labels(String path) => [
      for (final c in breadcrumbs(path, name)) c.label,
    ];
    List<String?> links(String path) => [
      for (final c in breadcrumbs(path, name)) c.path,
    ];

    expect(labels('/home'), ['Home']);
    expect(labels('/messages'), ['Messages']);
    expect(labels('/explore'), ['Explore']);
    expect(labels('/schedule'), ['Events']);
    expect(links('/explore'), [null], reason: "you're already there");

    // Pages opened from Explore lead back to it.
    expect(labels('/players/u2'), ['Explore', 'Player']);

    expect(labels('/teams/t1'), ['Teams', 'Cascades']);
    expect(labels('/teams/t1/roster'), ['Teams', 'Cascades', 'Roster']);
    expect(links('/teams/t1/roster'), [Routes.teams, Routes.team('t1'), null]);
    expect(labels('/teams/t1?section=roster'), ['Teams', 'Cascades', 'Roster']);
    expect(labels('/teams/t9'), ['Teams', 'Team']);

    expect(labels('/rankings?d=club-mixed'), ['Explore', 'Rankings']);
    expect(links('/rankings'), [Routes.explorePath, null]);
  });

  test('screen sizes follow the phone, tablet and desktop breakpoints', () {
    expect(ScreenSize.forWidth(390), ScreenSize.mobile);
    expect(ScreenSize.forWidth(800), ScreenSize.tablet);
    expect(ScreenSize.forWidth(1440), ScreenSize.desktop);
  });

  test('the shell lists the user\'s teams and counts unread', () async {
    final teams = FakeTeamRepository()
      ..teams['t2'] = teamWith({testUser.uid: TeamRole.owner}, id: 't2')
      ..teams['t1'] = teamWith({testUser.uid: TeamRole.owner});
    final dms = FakeDirectMessageRepository();
    final vm = ShellViewModel(
      authRepository: FakeAuthRepository(user: testUser),
      teamRepository: teams,
      directMessageRepository: dms,
      notificationRepository: FakeNotificationRepository(),
    );
    addTearDown(vm.dispose);
    await pumpEventQueue();
    expect(vm.teams.map((t) => t.id), unorderedEquals(['t1', 't2']));
    expect(vm.teamName('t1'), 'Team');
    expect(vm.unreadMessages, 0);

    dms.conversations['a_u1'] = Conversation(
      id: 'a_u1',
      participants: const ['a', 'u1'],
      lastMessage: 'hey',
      lastMessageAt: DateTime(2026, 10, 30),
      lastSenderId: 'a',
    );
    dms.conversations['b_u1'] = Conversation(
      id: 'b_u1',
      participants: const ['b', 'u1'],
      lastMessage: 'mine',
      lastMessageAt: DateTime(2026, 10, 30),
      lastSenderId: 'u1',
    );
    dms.emit();
    await pumpEventQueue();
    expect(vm.unreadMessages, 1);
  });

  group('notification offers', () {
    test('push is offered once after sign-in; Not now sticks', () async {
      final notifications = FakeNotificationRepository(offerPush: true);
      ShellViewModel shell() => ShellViewModel(
        authRepository: FakeAuthRepository(user: testUser),
        teamRepository: FakeTeamRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
        notificationRepository: notifications,
      );
      final vm = shell();
      addTearDown(vm.dispose);
      await pumpEventQueue();
      expect(vm.offerPush, isTrue);

      await vm.answerPushOffer.execute(false);
      expect(vm.offerPush, isFalse);
      expect(notifications.status, PushStatus.notDetermined);

      final again = shell();
      addTearDown(again.dispose);
      await pumpEventQueue();
      expect(again.offerPush, isFalse);
    });

    test('Turn on asks the system for permission', () async {
      final notifications = FakeNotificationRepository(offerPush: true);
      final vm = ShellViewModel(
        authRepository: FakeAuthRepository(user: testUser),
        teamRepository: FakeTeamRepository(),
        directMessageRepository: FakeDirectMessageRepository(),
        notificationRepository: notifications,
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      await vm.answerPushOffer.execute(true);
      expect(notifications.status, PushStatus.enabled);
      expect(vm.offerPush, isFalse);
    });

    test('joining a team asks about its notifications', () async {
      final teams = FakeTeamRepository()
        ..teams['t1'] = teamWith({testUser.uid: TeamRole.owner})
        ..teams['t2'] = teamWith({'u9': TeamRole.owner}, id: 't2');
      final notifications = FakeNotificationRepository();
      final vm = ShellViewModel(
        authRepository: FakeAuthRepository(user: testUser),
        teamRepository: teams,
        directMessageRepository: FakeDirectMessageRepository(),
        notificationRepository: notifications,
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      // Teams already on the list aren't new.
      expect(vm.joinedTeam, isNull);

      await teams.joinTeam('CODEt2', testUser);
      await pumpEventQueue();
      expect(vm.joinedTeam?.id, 't2');

      // No thanks turns the team's notifications off.
      await vm.answerTeamOffer.execute(false);
      expect(vm.joinedTeam, isNull);
      expect(
        notifications.prefs.isOnFor(NotificationCategory.chat, 't2'),
        isFalse,
      );
      expect(
        notifications.prefs.isOnFor(NotificationCategory.chat, 't1'),
        isTrue,
      );
    });

    test("creating a team doesn't ask", () async {
      final teams = FakeTeamRepository();
      final vm = ShellViewModel(
        authRepository: FakeAuthRepository(user: testUser),
        teamRepository: teams,
        directMessageRepository: FakeDirectMessageRepository(),
        notificationRepository: FakeNotificationRepository(),
      );
      addTearDown(vm.dispose);
      await pumpEventQueue();
      await teams.createTeam(
        const NewTeam(
          name: 'Mine',
          division: Division.mixed,
          level: CompetitionLevel.club,
        ),
        testUser,
      );
      await pumpEventQueue();
      expect(vm.joinedTeam, isNull);
    });
  });
}
