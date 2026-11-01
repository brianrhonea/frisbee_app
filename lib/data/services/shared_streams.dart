import 'dart:async';

/// Shares one upstream listener per key between every subscriber.
///
/// Firestore bills each listener for every document it returns, and the
/// app opens the same queries from many screens (and again each time a
/// screen is reopened). Routing those through here keeps one listener per
/// query: late subscribers get the latest value at once, and the listener
/// stays open for [grace] after the last subscriber leaves, so moving
/// between screens doesn't read everything again.
class SharedStreams {
  SharedStreams({this.grace = const Duration(minutes: 5)});

  /// The app-wide instance the Firebase repositories use.
  static final instance = SharedStreams();

  final Duration grace;
  final _entries = <String, _Entry<Object?>>{};

  /// Upstream listeners currently open, for tests and debugging.
  int get openCount => _entries.length;

  /// A stream of [key]'s values, opening [open] only if nothing is
  /// listening to [key] yet. [key] must identify the query exactly.
  Stream<T> get<T>(String key, Stream<T> Function() open) {
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        final entry = (_entries[key] ??= _Entry<T>(open)) as _Entry<T>;
        entry.add(controller, onDone: () => _drop(key, entry));
      },
      onCancel: () {
        final entry = _entries[key];
        if (entry == null) return;
        entry.remove(controller, grace, onIdle: () => _drop(key, entry));
      },
    );
    return controller.stream;
  }

  void _drop(String key, _Entry<Object?> entry) {
    if (!identical(_entries[key], entry)) return;
    _entries.remove(key);
    entry.close();
  }

  /// Closes every listener, e.g. when the signed-in user changes, so one
  /// account never sees another's cached data.
  void clear() {
    final all = _entries.values.toList();
    _entries.clear();
    for (final e in all) {
      e.close();
    }
  }
}

class _Entry<T> {
  _Entry(this._open);

  final Stream<T> Function() _open;
  final _listeners = <StreamController<T>>{};
  StreamSubscription<T>? _upstream;
  Timer? _idle;
  bool _hasValue = false;
  late T _value;

  void add(StreamController<T> c, {required void Function() onDone}) {
    _idle?.cancel();
    _idle = null;
    _listeners.add(c);
    if (_hasValue) c.add(_value);
    _upstream ??= _open().listen(
      (v) {
        _value = v;
        _hasValue = true;
        for (final l in _listeners.toList()) {
          l.add(v);
        }
      },
      // A failed or finished query isn't reused: the next subscriber
      // (e.g. a retry) opens a fresh one.
      onError: (Object e, StackTrace s) {
        for (final l in _listeners.toList()) {
          l.addError(e, s);
        }
        _end(onDone);
      },
      onDone: () => _end(onDone),
      cancelOnError: false,
    );
  }

  void _end(void Function() onDone) {
    _upstream?.cancel();
    _upstream = null;
    for (final l in _listeners.toList()) {
      l.close();
    }
    _listeners.clear();
    onDone();
  }

  void remove(
    StreamController<T> c,
    Duration grace, {
    required void Function() onIdle,
  }) {
    _listeners.remove(c);
    if (_listeners.isNotEmpty) return;
    _idle?.cancel();
    _idle = grace == Duration.zero ? null : Timer(grace, onIdle);
    if (grace == Duration.zero) onIdle();
  }

  void close() {
    _idle?.cancel();
    _upstream?.cancel();
    _upstream = null;
    for (final l in _listeners.toList()) {
      l.close();
    }
    _listeners.clear();
  }
}
