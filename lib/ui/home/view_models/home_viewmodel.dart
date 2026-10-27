import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../data/repositories/tournament/tournament_repository.dart';
import '../../../domain/models/app_user.dart';
import '../../../domain/models/team.dart';
import '../../../domain/models/tournament.dart';

/// Placeholder landing page data: the user's teams and the next few
/// tournaments. The landing page design will evolve.
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required AuthRepository authRepository,
    required TeamRepository teamRepository,
    required TournamentRepository tournamentRepository,
    DateTime Function()? clock,
  }) : _auth = authRepository,
       _clock = clock ?? DateTime.now {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _subs.add(
        teamRepository.watchMyTeams(uid).listen((t) {
          _teams = t;
          notifyListeners();
        }, onError: (_) {}),
      );
    }
    _subs.add(
      tournamentRepository.watchTournaments().listen((t) {
        _tournaments = t;
        notifyListeners();
      }, onError: (_) {}),
    );
  }

  final AuthRepository _auth;
  final DateTime Function() _clock;
  final List<StreamSubscription<Object?>> _subs = [];

  static const upcomingLimit = 5;

  AppUser? get user => _auth.currentUser;

  List<Team> _teams = const [];
  List<Team> get teams => _teams;

  List<Tournament> _tournaments = const [];
  List<Tournament> get upcomingTournaments {
    final now = _clock();
    return _tournaments
        .where((t) => t.isUpcoming(now))
        .take(upcomingLimit)
        .toList();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
