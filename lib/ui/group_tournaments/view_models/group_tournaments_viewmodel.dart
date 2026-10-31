import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/group_tournament/group_tournament_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/group_tournament.dart';
import '../../../domain/models/team.dart';

/// The group's Tournaments section. Owners and organizers see every
/// tournament; members see the ones they play in.
class GroupTournamentsViewModel extends ChangeNotifier {
  GroupTournamentsViewModel({
    required this.groupId,
    required TeamRepository teamRepository,
    required GroupTournamentRepository tournamentRepository,
    required AuthRepository authRepository,
  }) : _tournaments = tournamentRepository,
       _uid = authRepository.currentUser?.uid ?? '' {
    _teamSub = teamRepository
        .watchTeam(groupId)
        .listen(
          (t) {
            _group = t;
            _watch();
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
  }

  final String groupId;
  final GroupTournamentRepository _tournaments;
  final String _uid;
  late final StreamSubscription<Team?> _teamSub;
  StreamSubscription<List<GroupTournament>>? _sub;
  bool? _watchingAsOrganizer;

  Team? _group;
  List<GroupTournament> _list = const [];
  bool _loaded = false;
  Object? _error;

  bool get loaded => _loaded;
  Object? get error => _error;
  List<GroupTournament> get tournaments => _list;
  String get uid => _uid;

  /// Owners and organizers set tournaments up.
  bool get isOrganizer => _group?.canEdit(_uid) ?? false;

  /// The query depends on the role, so re-subscribe when it changes.
  void _watch() {
    if (_group == null) {
      _loaded = true;
      return;
    }
    final organizer = isOrganizer;
    if (_watchingAsOrganizer == organizer) return;
    _watchingAsOrganizer = organizer;
    _sub?.cancel();
    _sub = _tournaments
        .watchTournaments(groupId, uid: _uid, organizer: organizer)
        .listen(
          (list) {
            _list = list;
            _loaded = true;
            _error = null;
            notifyListeners();
          },
          onError: (Object e) {
            _error = e;
            _loaded = true;
            notifyListeners();
          },
        );
  }

  @override
  void dispose() {
    _teamSub.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
