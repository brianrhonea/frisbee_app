import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';

/// Who can host a new tournament, hat tournament or league: the groups,
/// schools or clubs, and teams, the user has Manage events on. Events are
/// run by one of those (so they have an organizer team, a page and
/// followers), so someone who runs none yet is pointed at starting one.
class HostEventViewModel extends ChangeNotifier {
  HostEventViewModel({
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _uid = authRepository.currentUser?.uid ?? '' {
    _sub = teamRepository
        .watchMyTeams(_uid)
        .listen(
          (l) {
            _hosts = [
              for (final t in l)
                if (t.has(_uid, TeamPermission.manageEvents)) t,
            ]..sort((a, b) => a.name.compareTo(b.name));
            _loaded = true;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
  }

  final String _uid;
  late final StreamSubscription<List<Team>> _sub;
  List<Team> _hosts = const [];
  bool _loaded = false;
  Object? _error;

  bool get loaded => _loaded;
  Object? get error => _error;

  /// Where the user can host, groups and clubs first.
  List<Team> get hosts => [
    ..._hosts.where((t) => t.kind.isGroupLike),
    ..._hosts.where((t) => !t.kind.isGroupLike),
  ];

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
