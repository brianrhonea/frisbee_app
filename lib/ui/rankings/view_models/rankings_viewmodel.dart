import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/ranking/ranking_repository.dart';
import '../../../data/repositories/team_elo/team_elo_repository.dart';
import '../../../domain/models/ranking.dart';
import '../../../domain/models/team_elo.dart';

/// Order of the rankings list: USA Ultimate's rank or our team Elo.
enum RankingSort { usau, elo }

class RankingsViewModel extends ChangeNotifier {
  RankingsViewModel({
    required RankingRepository rankingRepository,
    required TeamEloRepository teamEloRepository,
  }) : _repo = rankingRepository,
       _eloRepo = teamEloRepository {
    _subscribe();
    _subscribeElo();
  }

  final RankingRepository _repo;
  final TeamEloRepository _eloRepo;
  StreamSubscription<List<RankingDivision>>? _sub;
  StreamSubscription<List<TeamEloDivision>>? _eloSub;

  List<RankingDivision> _divisions = const [];
  List<RankingDivision> get divisions => _divisions;

  /// Elo by division key, then by team URL.
  Map<String, Map<String, TeamEloEntry>> _elo = const {};
  Map<String, TeamEloDivision> _eloDivisions = const {};

  bool _loading = true;
  bool get loading => _loading;

  Object? _error;
  Object? get error => _error;

  String _query = '';

  String? _selectedKey;

  RankingSort _sort = RankingSort.usau;
  RankingSort get sort => _sort;

  RankingDivision? get selected =>
      _divisions.where((d) => d.key == _selectedKey).firstOrNull ??
      _divisions.firstOrNull;

  /// Whether Elo ratings exist for the selected division. Elo is optional:
  /// until the Cloud Functions have run (or if Firestore is unavailable),
  /// the USAU rankings still work and the Elo toggle is hidden.
  bool get hasElo => _elo[selected?.key]?.isNotEmpty ?? false;

  /// When the selected division's Elo was last computed.
  DateTime? get eloUpdatedAt => _eloDivisions[selected?.key]?.updatedAt;

  TeamEloEntry? eloFor(RankingEntry entry) =>
      entry.teamUrl.isEmpty ? null : _elo[selected?.key]?[entry.teamUrl];

  /// The selected division's teams, filtered by the search query and ordered
  /// by [sort]. In Elo order, teams without a rating go last in USAU order.
  List<RankingEntry> get entries {
    final q = _query.trim().toLowerCase();
    final all = selected?.entries ?? const <RankingEntry>[];
    final filtered = q.isEmpty
        ? all
        : all.where((e) => e.teamName.toLowerCase().contains(q)).toList();
    if (_sort == RankingSort.usau || !hasElo) return filtered;
    double eloOf(RankingEntry e) => eloFor(e)?.elo ?? double.negativeInfinity;
    return [...filtered]..sort((a, b) {
      final byElo = eloOf(b).compareTo(eloOf(a));
      return byElo != 0 ? byElo : a.rank.compareTo(b.rank);
    });
  }

  void select(String key) {
    _selectedKey = key;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setSort(RankingSort sort) {
    _sort = sort;
    notifyListeners();
  }

  void retry() => _subscribe();

  void _subscribe() {
    _sub?.cancel();
    _loading = true;
    _error = null;
    notifyListeners();
    _sub = _repo.watchDivisions().listen(
      (d) {
        _divisions = d;
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

  void _subscribeElo() {
    _eloSub = _eloRepo.watchDivisions().listen(
      (divisions) {
        _eloDivisions = {for (final d in divisions) d.key: d};
        _elo = {
          for (final d in divisions)
            d.key: {
              for (final e in d.entries)
                if (e.teamUrl.isNotEmpty) e.teamUrl: e,
            },
        };
        notifyListeners();
      },
      // Elo is an optional extra; keep showing USAU rankings without it.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _eloSub?.cancel();
    super.dispose();
  }
}
