import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/ranking/ranking_repository.dart';
import '../../../domain/models/ranking.dart';
import '../../../domain/models/roster_sync.dart';
import 'usau_roster_viewmodel.dart';

/// Teams tab search: finds USA Ultimate teams by name across every
/// published ranking list.
class UsauTeamSearchViewModel extends ChangeNotifier {
  UsauTeamSearchViewModel({required RankingRepository rankingRepository}) {
    _sub = rankingRepository.watchDivisions().listen(
      (d) {
        _divisions = d;
        _loaded = true;
        notifyListeners();
      },
      onError: (Object e) {
        _error = e;
        notifyListeners();
      },
      onDone: () {
        _loaded = true;
        notifyListeners();
      },
    );
  }

  static const maxResults = 50;

  late final StreamSubscription<List<RankingDivision>> _sub;
  List<RankingDivision> _divisions = const [];

  bool _loaded = false;

  /// Rankings still loading; results fill in as divisions arrive.
  bool get searching => !_loaded && _error == null;

  Object? _error;
  Object? get error => _error;

  String _query = '';
  String get query => _query;

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  /// Ranking list labels to filter by, e.g. "Club Mixed".
  List<String> get divisions => [for (final d in _divisions) d.label];

  String? _division;

  /// Only search this ranking list; null searches all of them.
  String? get division => _division;

  void setDivision(String? label) {
    _division = label;
    notifyListeners();
  }

  /// Teams whose name contains the query: exact names first, then by rank.
  List<UsauCandidate> get results {
    final q = normalizeName(_query);
    if (q.isEmpty) return const [];
    int exact(UsauCandidate c) => normalizeName(c.entry.teamName) == q ? 0 : 1;
    final found =
        [
          for (final d in _divisions)
            if (_division == null || d.label == _division)
              for (final e in d.entries)
                if (e.teamUrl.isNotEmpty &&
                    normalizeName(e.teamName).contains(q))
                  (entry: e, division: d.label),
        ]..sort((a, b) {
          final byExact = exact(a).compareTo(exact(b));
          return byExact != 0 ? byExact : a.entry.rank.compareTo(b.entry.rank);
        });
    return found.take(maxResults).toList();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
