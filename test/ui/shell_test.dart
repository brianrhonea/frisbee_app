import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
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

    expect(labels('/home'), ['Community']);
    expect(labels('/messages'), ['Messages']);
    expect(labels('/explore'), ['Explore']);
    expect(links('/explore'), [null], reason: "you're already there");

    // Pages opened from Explore lead back to it.
    expect(labels('/tournaments'), ['Explore', 'Events']);
    expect(links('/tournaments'), [Routes.explorePath, null]);
    expect(labels('/tournaments/x1'), ['Explore', 'Events', 'Event']);
    expect(links('/tournaments/x1'), [
      Routes.explorePath,
      Routes.tournaments,
      null,
    ]);
    expect(labels('/rankings/team'), ['Explore', 'Rankings', 'Team']);
    expect(labels('/players/u2'), ['Explore', 'Player']);

    expect(labels('/teams/t1'), ['My teams', 'Cascades']);
    expect(labels('/teams/t1/roster'), ['My teams', 'Cascades', 'Roster']);
    expect(links('/teams/t1/roster'), [Routes.teams, Routes.team('t1'), null]);
    expect(labels('/teams/t1?section=roster'), [
      'My teams',
      'Cascades',
      'Roster',
    ]);
    expect(labels('/teams/t9'), ['My teams', 'Team']);
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
}
