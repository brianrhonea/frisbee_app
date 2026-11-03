import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

extension OpenLink on GoRouter {
  /// Opens a link from a notification, push or alert.
  ///
  /// Pages that open over the tabs (meetings, plays, chats, messages) are
  /// pushed, so back returns to where you were. Pages inside a tab are
  /// opened with `go`, which switches to that tab: pushing one would stack
  /// a second copy of pages the tab already holds (go_router then fails
  /// with duplicate page keys).
  void openLink(String location) {
    final matches = configuration.findMatch(Uri.parse(location)).matches;
    if (matches.isNotEmpty && matches.last is ShellRouteMatch) {
      go(location);
    } else {
      push(location);
    }
  }
}

/// Opens [location] from a page, keeping back to it where go_router can.
///
/// From a page inside a tab, everything is pushed. From a page over the
/// tabs (a post, a meeting), a page that lives in a tab (a profile, a team)
/// is opened with `go` instead: pushing it would build the tabs a second
/// time under the same page keys, which go_router can't do.
void openPage(BuildContext context, String location) {
  final router = GoRouter.of(context);
  final target = router.configuration.findMatch(Uri.parse(location)).matches;
  final inTab = target.isNotEmpty && target.last is ShellRouteMatch;
  final here = router.routerDelegate.currentConfiguration.matches;
  final overTabs = here.isNotEmpty && here.last is! ShellRouteMatch;
  if (inTab && overTabs) {
    router.go(location);
  } else {
    router.push(location);
  }
}
