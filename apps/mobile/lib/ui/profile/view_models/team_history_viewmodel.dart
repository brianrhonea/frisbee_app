import 'package:flutter/foundation.dart';

import '../../../data/repositories/team_history/team_history_repository.dart';
import '../../../domain/models/team_history.dart';
import '../../../utils/result.dart';

enum TeamHistoryStatus { loading, error, loaded }

/// The Team history section of a player's profile: loads on creation and
/// again on [load] (Retry).
class TeamHistoryViewModel extends ChangeNotifier {
  TeamHistoryViewModel({
    required this.uid,
    required this.isMe,
    required TeamHistoryRepository repository,
  }) : _repo = repository {
    load();
  }

  final String uid;

  /// Their own profile: an empty or failed history is said, not hidden.
  final bool isMe;
  final TeamHistoryRepository _repo;
  bool _disposed = false;
  int _token = 0;

  TeamHistoryStatus _status = TeamHistoryStatus.loading;
  TeamHistoryStatus get status => _status;

  Object? _error;
  Object? get error => _error;

  List<TeamHistoryEntry> _teams = const [];
  List<TeamHistoryEntry> get teams => _teams;

  bool get isEmpty => _status == TeamHistoryStatus.loaded && _teams.isEmpty;

  /// Whether any entry has more games than the server counts.
  bool get partial => _teams.any((t) => t.partial);

  /// Whether the section is on the page: always on your own profile; on
  /// someone else's only with entries (a private or hidden history comes
  /// back empty or refused, and says nothing).
  bool get visible => isMe || _teams.isNotEmpty;

  Future<void> load() async {
    final token = ++_token;
    _status = TeamHistoryStatus.loading;
    _error = null;
    notifyListeners();
    final r = await _repo.teamHistory(uid);
    if (_disposed || token != _token) return;
    switch (r) {
      case Ok(:final value):
        _teams = value;
        _status = TeamHistoryStatus.loaded;
      case Error(:final error):
        _error = error;
        _status = TeamHistoryStatus.error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
