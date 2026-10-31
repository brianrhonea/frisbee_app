import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../domain/models/direct_message.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Finds people by name to start a direct message with.
class PeopleSearchViewModel extends ChangeNotifier {
  PeopleSearchViewModel({
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
  }) : _dms = directMessageRepository,
       _auth = authRepository {
    search = Command1<List<UserProfile>, String>(_search);
    open = Command1<String, UserProfile>(_open);
  }

  static const minQueryLength = 2;

  final DirectMessageRepository _dms;
  final AuthRepository _auth;

  late final Command1<List<UserProfile>, String> search;

  /// Finds or starts the conversation; result value is its id.
  late final Command1<String, UserProfile> open;

  String _query = '';
  String get query => _query;

  List<UserProfile> get results => switch (search.result) {
    Ok(:final value) => value,
    _ => const [],
  };

  /// True once a search for the current query finished with no matches.
  bool get noMatches =>
      search.completed && results.isEmpty && _query.length >= minQueryLength;

  Future<Result<List<UserProfile>>> _search(String query) async {
    _query = query.trim();
    if (_query.length < minQueryLength) return const Result.ok([]);
    final result = await _dms.searchPeople(
      _query,
      excludeUid: _auth.currentUser?.uid ?? '',
    );
    // A newer query may have been typed while this one ran.
    if (query.trim() != _query) return const Result.ok([]);
    return result;
  }

  Future<Result<String>> _open(UserProfile other) async {
    final me = _auth.currentUser;
    if (me == null) return Result.error(Exception('Not signed in'));
    return _dms.openConversation(me, other);
  }
}
