import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/ranking/ranking_repository.dart';
import '../../../domain/models/ranking.dart';

class RankingsViewModel extends ChangeNotifier {
  RankingsViewModel({required RankingRepository rankingRepository})
    : _repo = rankingRepository {
    _subscribe();
  }

  final RankingRepository _repo;
  StreamSubscription<List<RankingDivision>>? _sub;

  List<RankingDivision> _divisions = const [];
  List<RankingDivision> get divisions => _divisions;

  bool _loading = true;
  bool get loading => _loading;

  Object? _error;
  Object? get error => _error;

  String _query = '';

  String? _selectedKey;

  RankingDivision? get selected =>
      _divisions.where((d) => d.key == _selectedKey).firstOrNull ??
      _divisions.firstOrNull;

  List<RankingEntry> get entries {
    final q = _query.trim().toLowerCase();
    final all = selected?.entries ?? const [];
    if (q.isEmpty) return all;
    return all.where((e) => e.teamName.toLowerCase().contains(q)).toList();
  }

  void select(String key) {
    _selectedKey = key;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
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

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
