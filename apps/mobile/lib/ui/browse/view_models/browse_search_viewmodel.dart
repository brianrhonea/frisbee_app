import 'package:flutter/foundation.dart';

import '../../../data/repositories/browse/browse_repository.dart';
import '../../../domain/models/player_profile.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Search for signed-out visitors: players, teams and groups by name.
class BrowseSearchViewModel extends ChangeNotifier {
  BrowseSearchViewModel({required BrowseRepository browseRepository})
    : _browse = browseRepository {
    search = Command1<void, String>(_search);
  }

  static const minQueryLength = 2;

  final BrowseRepository _browse;

  late final Command1<void, String> search;

  String _query = '';
  String get query => _query;

  List<PlayerProfile> _players = const [];
  List<PlayerProfile> get players => _players;

  List<TeamListing> _teams = const [];
  List<TeamListing> get teams => _teams;

  /// True once a search for the current query found nothing.
  bool get noMatches =>
      search.completed &&
      _query.length >= minQueryLength &&
      _players.isEmpty &&
      _teams.isEmpty;

  Future<Result<void>> _search(String text) async {
    final query = text.trim();
    _query = query;
    if (query.length < minQueryLength) {
      _players = const [];
      _teams = const [];
      notifyListeners();
      return const Result.ok(null);
    }
    final (players, teams) = await (
      _browse.searchPlayers(query),
      _browse.searchTeams(query),
    ).wait;
    // A newer query may have been typed while this one ran.
    if (query != _query) return const Result.ok(null);
    _players = switch (players) {
      Ok(:final value) => value,
      Error() => const [],
    };
    _teams = switch (teams) {
      Ok(:final value) => value,
      Error() => const [],
    };
    notifyListeners();
    return switch ((players, teams)) {
      (Error(:final error), Error()) => Result.error(error),
      _ => const Result.ok(null),
    };
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }
}
