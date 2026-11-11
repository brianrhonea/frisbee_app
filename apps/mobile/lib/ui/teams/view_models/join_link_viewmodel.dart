import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/team.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// An invite link someone tapped (`/join/<code>`): which team it joins,
/// whether the user is on it already, and joining it.
class JoinLinkViewModel extends ChangeNotifier {
  JoinLinkViewModel({
    required this.code,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _auth = authRepository {
    join = Command0<String>(_join);
    _resolve();
  }

  /// The team's invite code, from the link.
  final String code;
  final TeamRepository _teams;
  final AuthRepository _auth;
  final List<StreamSubscription<Object?>> _subs = [];

  late final Command0<String> join;

  bool _loaded = false;

  /// Whether the code has been looked up.
  bool get loaded => _loaded;

  Object? _error;

  /// Why the link doesn't work, e.g. the code was reset.
  Object? get error => _error;

  String? _teamId;
  String? get teamId => _teamId;

  TeamListing? _listing;

  /// The team's name if it's listed publicly; otherwise the screen says
  /// "a team".
  String? get teamName => _listing?.name;

  bool _member = false;

  /// The user is on the team already, so there's nothing to join.
  bool get alreadyMember => _member;

  Future<void> _resolve() async {
    final result = await _teams.resolveInviteCode(code);
    switch (result) {
      case Ok(:final value):
        _teamId = value;
        _subs.add(
          _teams.watchListing(value).listen((l) {
            _listing = l;
            notifyListeners();
          }, onError: (Object _) {}),
        );
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          _subs.add(
            _teams.watchMyTeams(uid).listen((teams) {
              final member = teams.any((t) => t.id == value);
              if (member == _member) return;
              _member = member;
              notifyListeners();
            }, onError: (Object _) {}),
          );
        }
      case Error(:final error):
        _error = error;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<Result<String>> _join() async {
    final user = _auth.currentUser;
    if (user == null) return Result.error(Exception('Not signed in'));
    if (_member && _teamId != null) return Result.ok(_teamId!);
    return _teams.joinTeam(code, user);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    join.dispose();
    super.dispose();
  }
}
