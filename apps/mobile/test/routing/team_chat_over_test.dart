// NAV1: a team chat opened from the Chats tab stacks over it (Chats > the
// team's chat list > the room), the tab bar stays on Chats, and each back
// slides one step. Opened from the Teams tab nothing changes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frisbee_app/routing/routes.dart';
import 'package:frisbee_app/routing/team_chat_links.dart';
import 'package:frisbee_app/ui/chat/widgets/chat_room_screen.dart';
import 'package:frisbee_app/ui/messages/widgets/inbox_screen.dart';
import 'package:frisbee_app/ui/shell/widgets/app_shell.dart';
import 'package:frisbee_app/ui/teams/widgets/team_home_screen.dart';
import 'package:frisbee_app/ui/teams/widgets/teams_screen.dart';
import 'package:go_router/go_router.dart';

import '../testing/app_harness.dart';

int _tab(WidgetTester t) =>
    t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

String _path(GoRouter r) =>
    r.routerDelegate.currentConfiguration.last.matchedLocation;

Future<GoRouter> _pumpOnChats(WidgetTester t) async {
  await pumpFullApp(t);
  final router = GoRouter.of(t.element(find.byType(Scaffold).first));
  router.go(Routes.messages);
  await t.pumpAndSettle();
  expect(find.byType(InboxScreen), findsOneWidget);
  return router;
}

void main() {
  final chatsIndex = ShellSection.tabs.indexOf(ShellSection.messages);
  final teamsIndex = ShellSection.tabs.indexOf(ShellSection.team);

  testWidgets('a room opened over Chats backs to the chat list, then Chats', (
    t,
  ) async {
    final router = await _pumpOnChats(t);
    openTeamChatOverChats(
      t.element(find.byType(InboxScreen)),
      't1',
      roomId: 'r1',
    );
    await t.pumpAndSettle();
    expect(find.byType(ChatRoomScreen), findsOneWidget);
    expect(_path(router), '/over/teams/t1/chats/r1');
    // The chat list sits under the room.
    expect(find.byType(TeamHomeScreen, skipOffstage: false), findsOneWidget);

    router.pop();
    await t.pumpAndSettle();
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(find.byType(TeamHomeScreen), findsOneWidget);

    router.pop();
    await t.pumpAndSettle();
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.byType(TeamHomeScreen), findsNothing);
    expect(_tab(t), chatsIndex);
  });

  testWidgets('see all chats opens the chat list over Chats', (t) async {
    final router = await _pumpOnChats(t);
    openTeamChatOverChats(t.element(find.byType(InboxScreen)), 't1');
    await t.pumpAndSettle();
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(_tab(t), chatsIndex);
  });

  testWidgets('room switch, settings and new room stay over Chats', (t) async {
    final router = await _pumpOnChats(t);
    openTeamChatOverChats(
      t.element(find.byType(InboxScreen)),
      't1',
      roomId: 'r1',
    );
    await t.pumpAndSettle();

    // Switch rooms (chat_room_screen pushReplacement).
    router.pushReplacement(Routes.asTeamOver(Routes.chatRoom('t1', 'r2')));
    await t.pumpAndSettle();
    expect(_path(router), '/over/teams/t1/chats/r2');

    router.push(Routes.asTeamOver(Routes.chatRoomSettings('t1', 'r2')));
    await t.pumpAndSettle();
    expect(_path(router), '/over/teams/t1/chats/r2/settings');
    router.pop();
    await t.pumpAndSettle();
    expect(_path(router), '/over/teams/t1/chats/r2');

    router.pop(); // the chat list, not Chats yet
    await t.pumpAndSettle();
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    router.push(Routes.asTeamOver(Routes.newChatRoom('t1')));
    await t.pumpAndSettle();
    expect(_path(router), '/over/teams/t1/chats/new');
    router.pop();
    await t.pumpAndSettle();
    router.pop();
    await t.pumpAndSettle();
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(_tab(t), chatsIndex);
  });

  testWidgets('deleting a room over Chats lands on the chat list', (t) async {
    final router = await _pumpOnChats(t);
    openTeamChatOverChats(
      t.element(find.byType(InboxScreen)),
      't1',
      roomId: 'r1',
    );
    await t.pumpAndSettle();
    router.push(Routes.asTeamOver(Routes.chatRoomSettings('t1', 'r1')));
    await t.pumpAndSettle();
    popToTeamChatList(t.element(find.byType(Scaffold).last), 't1');
    await t.pumpAndSettle();
    expect(find.byType(ChatRoomScreen), findsNothing);
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(_tab(t), chatsIndex);
  });

  testWidgets('from the Teams tab, rooms still open in the Teams tab', (
    t,
  ) async {
    await pumpFullApp(t);
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    router.go(Routes.teamChat('t1'));
    await t.pumpAndSettle();
    expect(_tab(t), teamsIndex);
    router.push(Routes.chatRoom('t1', 'r1'));
    await t.pumpAndSettle();
    expect(find.byType(ChatRoomScreen), findsOneWidget);
    expect(_path(router), '/teams/t1/chats/r1');
    router.pop();
    await t.pumpAndSettle();
    expect(find.byType(TeamHomeScreen), findsOneWidget);
    expect(find.byType(TeamsScreen), findsNothing);
    expect(_tab(t), teamsIndex);
  });
}
