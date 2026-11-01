import 'package:flutter/foundation.dart';

import '../../../data/repositories/profile/profile_repository.dart';
import '../../../domain/models/player_profile.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Finds players by name, school, hometown or team.
class PlayerSearchViewModel extends ChangeNotifier {
  PlayerSearchViewModel({required ProfileRepository profileRepository})
    : _profiles = profileRepository {
    search = Command1<List<PlayerProfile>, String>(_search);
  }

  static const minQueryLength = 2;

  final ProfileRepository _profiles;

  late final Command1<List<PlayerProfile>, String> search;

  String _query = '';
  String get query => _query;

  List<PlayerProfile> get results => switch (search.result) {
    Ok(:final value) => value,
    _ => const [],
  };

  /// True once a search for the current query finished with no matches.
  bool get noMatches =>
      search.completed && results.isEmpty && _query.length >= minQueryLength;

  Future<Result<List<PlayerProfile>>> _search(String query) async {
    _query = query.trim();
    if (_query.length < minQueryLength) return const Result.ok([]);
    final result = await _profiles.searchPlayers(_query);
    // A newer query may have been typed while this one ran.
    if (query.trim() != _query) return const Result.ok([]);
    return result;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }
}
