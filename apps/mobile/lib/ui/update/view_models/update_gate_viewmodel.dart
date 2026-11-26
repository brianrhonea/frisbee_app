import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/meta_flags/meta_flags_repository.dart';
import '../../../domain/models/meta_flags.dart';

/// Whether this build is still allowed to run, from `meta/flags.minBuild`
/// (contract: docs/specifications/contracts/meta-flags.md, #6).
///
/// Starts without blocking the app: [start] reads once (3 s) and then follows
/// the document live; the screen shows when the answer arrives. It fails OPEN:
/// a flags read that fails, times out or finds no document never shows the
/// update screen, and once a good answer has arrived a later failed read
/// keeps it. [recheck] runs again when the app comes back to the foreground.
class UpdateGateViewModel extends ChangeNotifier {
  UpdateGateViewModel({
    required MetaFlagsRepository repository,
    required this.platform,
    required this.build,
    this.timeout = const Duration(seconds: 3),
  }) : _repository = repository;

  final MetaFlagsRepository _repository;

  /// Null on a platform with no build gate (the app only ships on iOS and
  /// Android; desktop and test hosts are never blocked).
  final AppPlatform? platform;

  /// This build's number (the `+N` in pubspec.yaml).
  final int build;
  final Duration timeout;

  StreamSubscription<MetaFlags?>? _sub;
  MetaFlags? _flags;
  bool _disposed = false;

  /// The newest flags read, or null when none could be.
  MetaFlags? get flags => _flags;

  /// True when this build is below the lowest allowed: show the "Update
  /// required" screen and nothing else.
  bool get updateRequired {
    final p = platform;
    return p != null && !MetaFlags.isBuildAllowed(_flags, p, build);
  }

  /// The lowest build allowed, for the screen's text (null without a gate).
  int? get minBuild {
    final p = platform;
    final f = _flags;
    return p == null || f == null ? null : f.minBuildFor(p);
  }

  /// Reads once, then follows the document. Call without awaiting at app
  /// start.
  Future<void> start() async {
    if (platform == null) return;
    await recheck();
    if (_disposed) return;
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = _repository.watch().listen(
      _apply,
      onError: (Object _) {},
      onDone: () => _sub = null,
    );
  }

  /// Reads the flags again (the app resumed). A failed read changes nothing.
  Future<void> recheck() async {
    if (platform == null) return;
    final next = await _repository.read(timeout: timeout);
    if (_disposed) return;
    _apply(next);
    // A listener that ended on an error is started again here.
    if (_sub == null) _listen();
  }

  void _apply(MetaFlags? next) {
    // Unreadable: keep what was last read (nothing at first, so allowed).
    if (next == null || next == _flags) return;
    _flags = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
