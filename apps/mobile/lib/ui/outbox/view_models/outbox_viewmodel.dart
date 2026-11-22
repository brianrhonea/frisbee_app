import 'package:flutter/foundation.dart';

import '../../../data/repositories/outbox/outbox_repository.dart';
import '../../../domain/models/outbox.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The offline banner and the "waiting to send" list: whether Stall 10
/// can be reached, and what's queued until it can.
class OutboxViewModel extends ChangeNotifier {
  OutboxViewModel({required OutboxRepository outbox}) : _outbox = outbox {
    _outbox.addListener(notifyListeners);
    retry = Command1<void, String>((id) async {
      await _outbox.retry(id);
      return const Result.ok(null);
    });
    discard = Command1<void, String>((id) async {
      await _outbox.discard(id);
      return const Result.ok(null);
    });
  }

  final OutboxRepository _outbox;

  late final Command1<void, String> retry;
  late final Command1<void, String> discard;

  bool get online => _outbox.online;
  List<OutboxJob> get jobs => _outbox.jobs;
  int get waitingCount => _outbox.waitingCount;
  int get failedCount => _outbox.failedCount;

  /// Shown while offline, or while anything waits or was turned down.
  bool get showBanner => !online || waitingCount > 0 || failedCount > 0;

  /// The banner's line.
  String get bannerText {
    final waiting = waitingCount;
    final things = waiting == 1 ? '1 item' : '$waiting items';
    if (!online) {
      return waiting == 0
          ? "You're offline. What you send will go out when you're back."
          : "You're offline. $things will send when you're back.";
    }
    if (waiting > 0) return 'Sending $things…';
    return failedCount == 1
        ? "1 item couldn't be sent. Tap to review."
        : "$failedCount items couldn't be sent. Tap to review.";
  }

  /// Each item as it's queued.
  Stream<OutboxJob> get queued => _outbox.queued;

  /// "Waiting", "Sending…" or why it failed.
  static String stateOf(OutboxJob job) => switch (job.state) {
    OutboxState.waiting => 'Waiting to send',
    OutboxState.sending => 'Sending…',
    OutboxState.failed => job.error ?? "Couldn't be sent.",
  };

  @override
  void dispose() {
    _outbox.removeListener(notifyListeners);
    super.dispose();
  }
}

/// "Couldn't reach Stall 10. Your message will send by itself once it can."
String queuedNotice(OutboxJob job) =>
    "Couldn't reach Stall 10. Your ${job.label.toLowerCase()} will send by "
    'itself once it can.';
