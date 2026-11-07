/// Which conversations and chat rooms are on screen right now, by their
/// notification collapse id (e.g. `dm_{id}`, `chat_{team}_{room}`; see
/// functions/src/notifications/model.ts).
///
/// A thread's view registers a check while it's built; the check says
/// whether it's actually showing (its route on top, its tab selected). A
/// notice for a thread that's showing isn't announced, and is cleared.
abstract final class OnScreen {
  static final _checks = <String, List<bool Function()>>{};

  /// Registers [check] for [key]; call the returned function to remove it.
  static void Function() register(String key, bool Function() check) {
    (_checks[key] ??= []).add(check);
    return () {
      final list = _checks[key];
      list?.remove(check);
      if (list != null && list.isEmpty) _checks.remove(key);
    };
  }

  /// Whether a view of [key] is on screen.
  static bool isShowing(String key) =>
      _checks[key]?.any((check) => check()) ?? false;

  /// Whether [key] has views, none of them showing (e.g. open in a tab
  /// that's in the background). False when it has none at all.
  static bool isHidden(String key) {
    final list = _checks[key];
    return list != null && list.isNotEmpty && !list.any((check) => check());
  }
}
