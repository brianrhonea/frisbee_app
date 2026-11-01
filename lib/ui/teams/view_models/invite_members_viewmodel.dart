import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/direct_message/direct_message_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/direct_message.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// Finds people in the directory and invites them to [team]. Owners and
/// organizers only (the rules check).
class InviteMembersViewModel extends ChangeNotifier {
  InviteMembersViewModel({
    required this.team,
    required TeamRepository teamRepository,
    required DirectMessageRepository directMessageRepository,
    required AuthRepository authRepository,
    this.debounce = const Duration(milliseconds: 300),
  }) : _teams = teamRepository,
       _people = directMessageRepository,
       _auth = authRepository {
    invite = Command1<void, UserProfile>(_invite);
  }

  final Team team;
  final TeamRepository _teams;
  final DirectMessageRepository _people;
  final AuthRepository _auth;

  static const minQueryLength = 2;

  /// How long typing pauses before searching.
  final Duration debounce;

  late final Command1<void, UserProfile> invite;

  Timer? _timer;
  String _query = '';
  int _searchId = 0;

  List<UserProfile> _results = const [];
  List<UserProfile> get results => _results;

  bool _searching = false;
  bool get searching => _searching;

  Object? _error;
  Object? get error => _error;

  final Set<String> _invited = {};

  String get query => _query;

  bool isMember(String uid) => team.members.containsKey(uid);

  /// Invited while this dialog was open.
  bool wasInvited(String uid) => _invited.contains(uid);

  /// Searches for [query] once typing pauses.
  void search(String query) {
    _query = query.trim();
    _timer?.cancel();
    if (_query.length < minQueryLength) {
      _searchId++;
      _results = const [];
      _searching = false;
      _error = null;
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    _timer = Timer(debounce, _run);
  }

  Future<void> _run() async {
    final id = ++_searchId;
    final result = await _people.searchPeople(
      _query,
      excludeUid: _auth.currentUser?.uid ?? '',
    );
    // A newer search started while this one ran.
    if (id != _searchId) return;
    _searching = false;
    switch (result) {
      case Ok(:final value):
        _results = value;
        _error = null;
      case Error(:final error):
        _results = const [];
        _error = error;
    }
    notifyListeners();
  }

  Future<Result<void>> _invite(UserProfile person) async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    if (isMember(person.uid)) {
      return Result.error(Exception('${person.name} is already a member.'));
    }
    final result = await _teams.inviteToTeam(team, person.uid, user);
    if (result is Ok) {
      _invited.add(person.uid);
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    _timer?.cancel();
    invite.dispose();
    super.dispose();
  }
}
