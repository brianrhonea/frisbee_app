import 'package:flutter/foundation.dart';

import '../../../data/repositories/moderation/moderation_repository.dart';
import '../../../domain/models/moderation.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// A team's open reports, for its owner and members who may moderate or
/// manage the team: remove what was reported, or dismiss the report.
class TeamReportsViewModel extends ChangeNotifier {
  TeamReportsViewModel({
    required ModerationRepository repository,
    required this.teamId,
  }) : _repo = repository {
    load = Command0(_load)..addListener(notifyListeners);
    resolve = Command1(_resolve)..addListener(notifyListeners);
    load.execute();
  }

  final ModerationRepository _repo;
  final String teamId;

  List<ReportInfo> _reports = const [];
  List<ReportInfo> get reports => _reports;
  bool _loaded = false;
  bool get loaded => _loaded;

  late final Command0<void> load;

  /// (report id, remove?): removes the content, or dismisses the report.
  late final Command1<void, (String, bool)> resolve;

  Future<Result<void>> _load() async {
    final r = await _repo.teamReports(teamId);
    _loaded = true;
    if (r case Ok(:final value)) _reports = value;
    notifyListeners();
    return switch (r) {
      Ok() => const Result.ok(null),
      Error(:final error) => Result.error(error),
    };
  }

  Future<Result<void>> _resolve((String, bool) a) async {
    final r = await _repo.resolveTeamReport(teamId, a.$1, remove: a.$2);
    if (r is Ok) {
      _reports = [
        for (final x in _reports)
          if (x.id != a.$1) x,
      ];
      notifyListeners();
    }
    return r;
  }

  @override
  void dispose() {
    load.dispose();
    resolve.dispose();
    super.dispose();
  }
}
