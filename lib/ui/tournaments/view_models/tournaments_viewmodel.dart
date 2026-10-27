import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/tournament/tournament_repository.dart';
import '../../../domain/models/tournament.dart';

class TournamentsViewModel extends ChangeNotifier {
  TournamentsViewModel({
    required TournamentRepository tournamentRepository,
    DateTime Function()? clock,
  }) : _repo = tournamentRepository,
       _clock = clock ?? DateTime.now {
    _subscribe();
  }

  final TournamentRepository _repo;
  final DateTime Function() _clock;
  StreamSubscription<List<Tournament>>? _sub;

  List<Tournament> _all = const [];

  bool _loading = true;
  bool get loading => _loading;

  Object? _error;
  Object? get error => _error;

  String _query = '';
  String get query => _query;

  String? _level;
  String? get level => _level;

  String? _division;
  String? get division => _division;

  bool _showPast = false;
  bool get showPast => _showPast;

  bool get isEmpty => _all.isEmpty;

  List<String> get levels =>
      _all
          .map((t) => t.competitionLevel)
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  List<String> get divisions =>
      _all.expand((t) => t.divisions).toSet().toList()..sort();

  /// Tournaments matching the current filters. Upcoming events are sorted
  /// soonest first; past events most recent first.
  List<Tournament> get tournaments {
    final now = _clock();
    final q = _query.trim().toLowerCase();
    final list = _all.where((t) {
      if (t.isUpcoming(now) == _showPast) return false;
      if (_level != null && t.competitionLevel != _level) return false;
      if (_division != null && !t.divisions.contains(_division)) return false;
      if (q.isNotEmpty &&
          !t.name.toLowerCase().contains(q) &&
          !t.location.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    return _showPast ? list.reversed.toList() : list;
  }

  Tournament? byId(String id) => _all.where((t) => t.id == id).firstOrNull;

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setLevel(String? level) {
    _level = level;
    notifyListeners();
  }

  void setDivision(String? division) {
    _division = division;
    notifyListeners();
  }

  void setShowPast(bool past) {
    _showPast = past;
    notifyListeners();
  }

  void retry() => _subscribe();

  void _subscribe() {
    _sub?.cancel();
    _loading = true;
    _error = null;
    notifyListeners();
    _sub = _repo.watchTournaments().listen(
      (list) {
        _all = list;
        _loading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object e) {
        _error = e;
        _loading = false;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
