import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/domain/models/direct_message.dart';
import 'package:frisbee_app/domain/models/team.dart';
import 'package:frisbee_app/ui/core/ui/layout.dart';
import 'package:frisbee_app/ui/shell/view_models/shell_viewmodel.dart';
import 'package:frisbee_app/ui/shell/widgets/app_shell.dart';

import '../testing/fakes.dart';

void main() {
  test('breadcrumbs name the page under the community', () {
    String? name(String id) => id == 't1' ? 'Cascades' : null;
    expect(breadcrumbs('/home', name), ['Your community', 'Community feed']);
    expect(breadcrumbs('/messages', name), ['Your community', 'Messages']);
    expect(breadcrumbs('/teams/t1', name), ['Your community', 'Cascades']);
    expect(breadcrumbs('/teams/t1/roster', name), [
      'Your community',
      'Cascades',
      'Roster',
    ]);
    expect(breadcrumbs('/teams/t1?section=roster', name), [
      'Your community',
      'Cascades',
      'Roster',
    ]);
    expect(breadcrumbs('/teams/t9', name), ['Your community', 'Team']);
    expect(breadcrumbs('/explore', name), ['Your community', 'Explore']);
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
