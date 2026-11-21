import 'package:frisbee_app/data/repositories/moderation/moderation_repository.dart';
import 'package:frisbee_app/domain/models/moderation.dart';
import 'package:frisbee_app/utils/result.dart';

/// A report the fake was sent.
typedef SentReport = ({
  ReportTarget target,
  ReportReason reason,
  String? details,
  bool block,
});

/// [ModerationRepository] in memory: records reports and blocks.
class FakeModerationRepository extends ModerationRepository {
  FakeModerationRepository({BlockList blocks = BlockList.empty})
    : _current = blocks;

  BlockList _current;
  final reports = <SentReport>[];
  final blocked = <String>[];
  final unblocked = <String>[];
  List<ReportInfo> teamQueue = [];
  final resolved = <(String, bool)>[];
  Exception? nextError;

  @override
  bool get enabled => true;

  @override
  BlockList get current => _current;

  set current(BlockList b) {
    _current = b;
    notifyListeners();
  }

  Result<T>? _fail<T>() {
    final e = nextError;
    if (e == null) return null;
    nextError = null;
    return Result.error(e);
  }

  @override
  Future<Result<bool>> report(
    ReportTarget target,
    ReportReason reason, {
    String? details,
    bool block = false,
    String? authorId,
  }) async {
    if (_fail<bool>() case final e?) return e;
    reports.add((
      target: target,
      reason: reason,
      details: details,
      block: block,
    ));
    if (block && authorId != null) {
      current = BlockList(
        mine: _current.mine,
        hidden: {..._current.hidden, authorId},
      );
    }
    return Result.ok(block);
  }

  @override
  Future<Result<void>> block(String uid) async {
    if (_fail<void>() case final e?) return e;
    blocked.add(uid);
    current = BlockList(
      mine: [..._current.mine, BlockedAccount(uid: uid, name: uid)],
      hidden: {..._current.hidden, uid},
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> unblock(String uid) async {
    if (_fail<void>() case final e?) return e;
    unblocked.add(uid);
    current = BlockList(
      mine: [
        for (final b in _current.mine)
          if (b.uid != uid) b,
      ],
      hidden: {..._current.hidden}..remove(uid),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<List<ReportInfo>>> teamReports(String teamId) async =>
      _fail<List<ReportInfo>>() ?? Result.ok(teamQueue);

  @override
  Future<Result<void>> resolveTeamReport(
    String teamId,
    String reportId, {
    required bool remove,
  }) async {
    if (_fail<void>() case final e?) return e;
    resolved.add((reportId, remove));
    return const Result.ok(null);
  }
}
