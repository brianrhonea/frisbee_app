import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/ranking/ranking_repository.dart';
import '../../../data/repositories/usau_team/usau_team_repository.dart';
import '../../../domain/models/ranking.dart';
import '../../../domain/models/usau_team.dart';
import '../../../utils/result.dart';

/// A team's USA Ultimate standing for its public page: ranking, season
/// record and tournament schedule, from the linked USA Ultimate page.
class TeamUsauViewModel extends ChangeNotifier {
  TeamUsauViewModel({
    required this.url,
    this.name = '',
    required UsauTeamRepository usauTeamRepository,
    RankingRepository? rankingRepository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    usauTeamRepository.getTeam(url).then((r) {
      if (_disposed) return;
      switch (r) {
        case Ok(:final value):
          _team = value;
        case Error(:final error):
          _error = error;
      }
      _teamLoaded = true;
      notifyListeners();
    });
    _rankingSub = rankingRepository?.watchDivisions().listen(
      _findRanking,
      onError: (Object _) {},
    );
  }

  /// Schedule rows shown; the full list is on the USA Ultimate page.
  static const scheduleLimit = 3;

  final String url;

  /// The team's name on USA Ultimate, if known.
  final String name;
  final DateTime Function() _clock;
  StreamSubscription<List<RankingDivision>>? _rankingSub;
  bool _disposed = false;

  UsauTeam? _team;
  bool _teamLoaded = false;
  Object? _error;
  RankingEntry? _ranking;
  String? _division;

  bool get loaded => _teamLoaded;
  Object? get error => _error;

  /// Where the team stands in its division, once the rankings list that
  /// has it loads; null if it isn't ranked.
  RankingEntry? get ranking => _ranking;

  /// The ranking list the team is on, e.g. "Club Mixed".
  String? get division => _division;

  /// Season wins and losses: the rankings' record when the team is ranked,
  /// else the games on its page. Null with no games either.
  ({int wins, int losses})? get record {
    final r = _ranking;
    if (r?.wins case final w? when r?.losses != null) {
      return (wins: w, losses: r!.losses!);
    }
    final t = _team;
    if (t == null || t.wins + t.losses == 0) return null;
    return (wins: t.wins, losses: t.losses);
  }

  /// Upcoming tournaments, soonest first, then the latest finished ones
  /// (with placement) to fill [scheduleLimit] rows.
  List<UsauEvent> get schedule {
    final now = _clock();
    final far = DateTime.utc(9999);
    final events = [...?_team?.events]
      ..sort((a, b) => (a.startDate ?? far).compareTo(b.startDate ?? far));
    final upcoming = events.where((e) => e.isUpcoming(now)).toList();
    final past = events.where((e) => !e.isUpcoming(now)).toList().reversed;
    return [...upcoming, ...past].take(scheduleLimit).toList();
  }

  bool isUpcoming(UsauEvent e) => e.isUpcoming(_clock());

  void _findRanking(List<RankingDivision> divisions) {
    final key = normalizeUsauUrl(url);
    for (final d in divisions) {
      for (final e in d.entries) {
        if (e.teamUrl.isEmpty || normalizeUsauUrl(e.teamUrl) != key) continue;
        _ranking = e;
        _division = d.label;
        // Found it; the other lists aren't needed.
        _rankingSub?.cancel();
        _rankingSub = null;
        notifyListeners();
        return;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _rankingSub?.cancel();
    super.dispose();
  }
}

/// [url] in a form that compares equal however USA Ultimate printed it:
/// any scheme, letter case, percent-encoding or trailing slash.
String normalizeUsauUrl(String url) {
  var s = url.trim();
  try {
    s = Uri.decodeFull(s);
  } catch (_) {
    // Leave malformed escapes as they are.
  }
  return s
      .toLowerCase()
      .replaceFirst(RegExp(r'^https?://'), '')
      .replaceFirst(RegExp(r'^www\.'), '')
      .replaceFirst(RegExp(r'/+$'), '');
}
