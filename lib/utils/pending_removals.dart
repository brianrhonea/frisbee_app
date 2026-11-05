import 'dart:async';

/// Removals that wait out an undo window: the item is hidden at once and
/// [commit] runs when the window ends, unless [undo] is called first. Lets
/// a list delete with an "Undo" toast instead of an "Are you sure?" dialog.
class PendingRemovals<T> {
  PendingRemovals({
    required this.keyOf,
    required this.commit,
    required this.onChange,
    this.window = undoWindow,
  });

  /// How long "Undo" is offered.
  static const undoWindow = Duration(seconds: 5);

  final String Function(T item) keyOf;
  final void Function(T item) commit;

  /// Called when an item is hidden or comes back.
  final void Function() onChange;
  final Duration window;

  final Map<String, (T, Timer)> _pending = {};

  bool isPending(T item) => _pending.containsKey(keyOf(item));

  /// [items] without the ones waiting to be removed.
  List<T> visible(Iterable<T> items) => [
    for (final i in items)
      if (!isPending(i)) i,
  ];

  void remove(T item) {
    final key = keyOf(item);
    _pending.remove(key)?.$2.cancel();
    _pending[key] = (
      item,
      Timer(window, () {
        _pending.remove(key);
        commit(item);
      }),
    );
    onChange();
  }

  void undo(T item) {
    if (_pending.remove(keyOf(item)) case (_, final timer)?) {
      timer.cancel();
      onChange();
    }
  }

  /// Commits everything still waiting when the screen closes, with [using]
  /// in place of [commit] (which may report back to a disposed view model).
  void flush(void Function(T item) using) {
    final waiting = _pending.values.toList();
    _pending.clear();
    for (final (item, timer) in waiting) {
      timer.cancel();
      using(item);
    }
  }
}
