import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/team/team_repository.dart';
import '../../../domain/models/invite_code.dart';
import '../../../utils/result.dart';

/// A team's invite code that rotates while it's on screen: a fresh code
/// every [InviteCode.rotateEvery], each working for
/// [InviteCode.codeLifetime]. Codes are minted only after [show], so a
/// team page that nobody opens the code on costs nothing.
class InviteCodeViewModel extends ChangeNotifier {
  InviteCodeViewModel({
    required this.teamId,
    required TeamRepository teamRepository,
    required AuthRepository authRepository,
  }) : _teams = teamRepository,
       _auth = authRepository;

  final String teamId;
  final TeamRepository _teams;
  final AuthRepository _auth;

  Timer? _ticker;
  bool _minting = false;
  bool _disposed = false;

  bool _showing = false;

  /// Whether the code is on screen (and rotating).
  bool get showing => _showing;

  InviteCode? _code;

  /// The code to share; null until the first one is minted.
  String? get code => _code?.code;

  int _secondsLeft = 0;

  /// Seconds until the next code replaces this one.
  int get secondsLeft => _secondsLeft;

  Object? _error;

  /// Why the last code couldn't be minted; showing stops when one fails.
  Object? get error => _error;

  /// Shows a fresh code and starts rotating it.
  void show() {
    if (_showing) return;
    _showing = true;
    _error = null;
    notifyListeners();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _rotate();
  }

  /// Hides the code and stops minting new ones. The last one still works
  /// until it expires.
  void hide() {
    _ticker?.cancel();
    _ticker = null;
    _showing = false;
    _code = null;
    _secondsLeft = 0;
    notifyListeners();
  }

  void _tick() {
    if (_secondsLeft > 0) {
      _secondsLeft--;
      notifyListeners();
    }
    if (_secondsLeft == 0) _rotate();
  }

  Future<void> _rotate() async {
    if (_minting) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _minting = true;
    final result = await _teams.createInviteCode(teamId, uid);
    _minting = false;
    if (_disposed || !_showing) return;
    switch (result) {
      case Ok(:final value):
        _code = value;
        _secondsLeft = InviteCode.rotateEvery.inSeconds;
      case Error(:final error):
        hide();
        _error = error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}
