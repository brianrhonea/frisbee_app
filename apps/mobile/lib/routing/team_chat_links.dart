import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

/// `extra` that tells a team page opened over another page to appear at
/// once, because a chat page is about to cover it.
const stackedUnder = 'stacked-under';

/// Opens a team's chat from the Chats tab, over it: the team's chat list,
/// and over it [roomId]'s room if given. Back slides from the room to the
/// list, then to Chats, and the tab bar never leaves Chats.
void openTeamChatOverChats(
  BuildContext context,
  String teamId, {
  String? roomId,
}) {
  final list = Routes.teamChat(teamId);
  if (roomId == null) {
    context.push(Routes.asTeamOver(list));
    return;
  }
  // Two pushes made together would both start from the page showing and
  // the second would drop the first, so the room waits for the list.
  final router = GoRouter.of(context);
  final listPath = Routes.teamOver(teamId);
  void whenListIsUp() {
    if (router.routerDelegate.currentConfiguration.last.matchedLocation !=
        listPath) {
      return;
    }
    router.routerDelegate.removeListener(whenListIsUp);
    scheduleMicrotask(
      () => router.push(Routes.asTeamOver(Routes.chatRoom(teamId, roomId))),
    );
  }

  router.routerDelegate.addListener(whenListIsUp);
  router.push(Routes.asTeamOver(list), extra: stackedUnder);
}

/// Whether the page showing is a team opened over another page
/// ([Routes.teamOver], e.g. over the Chats tab) rather than in the Teams tab.
bool inTeamOver(BuildContext context) =>
    GoRouterState.of(context).uri.path.startsWith('${Routes.teamsOverPath}/');

/// [teamsLocation] (a `/teams/...` page) in the context the page showing
/// was opened from: its `/over/teams/...` copy over the Chats tab (or a
/// tournament), else unchanged for the Teams tab. Switching context would
/// change tabs underneath the user.
String inSameContext(BuildContext context, String teamsLocation) =>
    inTeamOver(context) ? Routes.asTeamOver(teamsLocation) : teamsLocation;

/// Pops pages of a team's chat (rooms, their settings) off [context]'s
/// stack until the team's chat list shows, for after a room is deleted.
/// In the Teams tab that's a plain `go` to the list.
void popToTeamChatList(BuildContext context, String teamId) {
  if (!inTeamOver(context)) {
    context.go(Routes.teamChat(teamId));
    return;
  }
  final router = GoRouter.of(context);
  final list = Routes.teamOver(teamId);
  while (router.canPop() &&
      router.routerDelegate.currentConfiguration.last.matchedLocation != list) {
    router.pop();
  }
}
