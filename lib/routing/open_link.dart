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
