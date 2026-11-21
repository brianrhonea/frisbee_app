import 'package:flutter/foundation.dart';

import '../../../data/repositories/moderation/moderation_repository.dart';
import '../../../domain/models/moderation.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// The Report sheet: a reason, optional details, and "also block".
class ReportViewModel extends ChangeNotifier {
  ReportViewModel({
    required ModerationRepository repository,
    required this.target,
    this.authorId,
  }) : _repo = repository {
    send = Command0(_send)..addListener(notifyListeners);
  }

  final ModerationRepository _repo;
  final ReportTarget target;
  final String? authorId;

  ReportReason? _reason;
  ReportReason? get reason => _reason;
  String details = '';
  bool _block = false;
  bool get alsoBlock => _block;

  /// Ok(true) once sent with the author blocked.
  late final Command0<bool> send;

  bool get canSend => _reason != null && !send.running;

  void pick(ReportReason r) {
    _reason = r;
    notifyListeners();
  }

  void setBlock(bool on) {
    _block = on;
    notifyListeners();
  }

  Future<Result<bool>> _send() async {
    final r = _reason;
    if (r == null) return Result.error(Exception('Pick a reason.'));
    return _repo.report(
      target,
      r,
      details: details,
      block: _block,
      authorId: authorId,
    );
  }

  @override
  void dispose() {
    send.dispose();
    super.dispose();
  }
}
