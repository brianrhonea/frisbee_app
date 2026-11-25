import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

extension OpenLink on GoRouter {
  /// Opens a link from a notification, push or alert.
  ///
  /// Pages that open over the tabs (meetings, plays, chats, messages) are
  /// pushed, so back returns to where you were. Pages inside a tab are
  /// opened with `go`, which switches to that tab: pushing one would stack
  /// a second copy of pages the tab already holds (go_router then fails
  /// with duplicate page keys).
  ///
  /// A link to the page already open does nothing, and one to another of
  /// the same kind (another conversation, from a conversation) replaces
  /// it, so following notifications never piles up pages to back out of.
  void openLink(String location) {
    final here = routerDelegate.currentConfiguration;
    if (here.matches.isNotEmpty && here.matches.last is! ShellRouteMatch) {
      location = _personOver(location);
    }
    final target = Uri.parse(location);
    final matches = configuration.findMatch(target);
    if (matches.matches.isNotEmpty && matches.matches.last is ShellRouteMatch) {
      go(location);
      return;
    }
    if (here.uri.path == target.path) return;
    final hereLast = here.isEmpty ? null : here.last;
    final targetLast = matches.isEmpty ? null : matches.last;
    if (hereLast != null &&
        targetLast != null &&
        hereLast.route == targetLast.route) {
      pushReplacement(location);
    } else {
      push(location);
    }
  }
}

extension OpenFromOutside on GoRouter {
  /// Opens a notification tapped outside the app (a push), with back
  /// going to the page it belongs under, not wherever the app was left:
  /// a conversation over Messages, a team chat over its team, a post over
  /// Home.
  ///
  /// Pages that sit under a tab or another page are opened with `go`,
  /// which builds that page beneath them. Pages that open over the tabs
  /// on their own (a post, a team's event or meeting, a tournament) are
  /// pushed over the tab they belong to ([pushParent]).
  void openFromOutside(String location) {
    final parent = pushParent(location);
    if (parent == null) {
      go(location);
      return;
    }
    // Over the parent page, in one step, whatever was open before.
    routeInformationProvider.push<Object?>(
      location,
      base: configuration.findMatch(Uri.parse(parent)),
    );
  }
}

extension OpenFromNotifications on GoRouter {
  /// Opens a notification tapped in the Notifications list. Back goes to
  /// the page it belongs under, as for a push ([openFromOutside]): a team
  /// chat to its team, a conversation to Chats, a post to Home; not back
  /// to Notifications. Pages with nothing above them (a person, follow
  /// requests) open over the list ([openLink]), so back returns to it.
  void openFromNotifications(String location) {
    final path = Uri.parse(location).path;
    if (_overList.hasMatch(path)) {
      openLink(location);
    } else {
      openFromOutside(location);
    }
  }
}

/// Notification links with no page of their own above them.
final _overList = RegExp(
  r'^/(players|people|notifications|settings/follow-requests)(/|$)',
);

final _overTabs = RegExp(
  r'^/(posts|team-events|team-meetings|my-events|tournaments|group-tournaments)'
  r'(?:/([^/?#]+))?',
);

/// The page a notification's page opened over the tabs belongs under, or
/// null when go_router already builds one beneath it.
String? pushParent(String location) {
  final m = _overTabs.firstMatch(location);
  if (m == null) return null;
  final id = m.group(2);
  return switch (m.group(1)) {
    'posts' => Routes.home,
    'team-events' || 'team-meetings' when id != null => Routes.teamEvents(id),
    'group-tournaments' when id != null => Routes.team(id),
    'my-events' => Routes.schedule,
    'tournaments' => Routes.explorePath,
    _ => null,
  };
}

/// Opens [location] from a page, keeping back to it where go_router can.
///
/// From a page inside a tab, everything is pushed. A profile opened from
/// a page over the tabs (Following, a notification) opens over it too
/// ([Routes.personOver]), so back returns there. From a page over the
/// tabs (a post, a meeting), a page that lives in a tab (a profile, a team)
/// is opened with `go` instead: pushing it would build the tabs a second
/// time under the same page keys, which go_router can't do.
void openPage(BuildContext context, String location) {
  final router = GoRouter.of(context);
  final here = router.routerDelegate.currentConfiguration.matches;
  final overTabs = here.isNotEmpty && here.last is! ShellRouteMatch;
  if (overTabs) location = _personOver(location);
  final target = router.configuration.findMatch(Uri.parse(location)).matches;
  final inTab = target.isNotEmpty && target.last is ShellRouteMatch;
  if (inTab && overTabs) {
    router.go(location);
  } else {
    router.push(location);
  }
}

final _player = RegExp(r'^/players/([^/?#]+)$');

/// A profile's tab link ([Routes.player]) as the same profile over the
/// tabs, so opening it from a page over them keeps a way back.
String _personOver(String location) => switch (_player.firstMatch(location)) {
  final m? => Routes.personOver(m.group(1)!),
  null => location,
};

/// Leaves this page (one over the tabs, like a tournament's Respond) for
/// [location], a page that also opens over the tabs, keeping what's
/// beneath: back to it when it's the page underneath, else in this page's
/// place. With nothing beneath (opened from a notification), it opens over
/// the page it belongs under ([GoRouter.openFromOutside]). Never `go`,
/// which would drop the pages and the tabs below and leave no way back.
/// Where the user is: the top page's location, a pushed page's own (the
/// configuration's uri is the page under pushed ones).
String currentLocationOf(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  if (config.matches.isEmpty) return config.uri.toString();
  final last = config.matches.last;
  if (last is ImperativeRouteMatch) return last.matches.uri.toString();
  return config.uri.toString();
}

void leaveFor(BuildContext context, String location) {
  final router = GoRouter.of(context);
  final matches = router.routerDelegate.currentConfiguration.matches;
  final target = Uri.parse(location).path;
  if (matches.length >= 2 &&
      matches[matches.length - 2].matchedLocation == target) {
    context.pop();
  } else if (context.canPop()) {
    context.pushReplacement(location);
  } else {
    router.openFromOutside(location);
  }
}
