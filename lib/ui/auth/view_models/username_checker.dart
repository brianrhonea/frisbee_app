import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../domain/models/username.dart';
import '../../../utils/result.dart';

/// Where a typed username stands.
enum UsernameStatus { empty, invalid, checking, available, taken, failed }

/// Checks a username as it's typed: its format at once, whether it's free
/// after a short pause.
class UsernameChecker extends ChangeNotifier {
  UsernameChecker({
    required AuthRepository authRepository,
    this.delay = const Duration(milliseconds: 400),
  }) : _auth = authRepository;

  final AuthRepository _auth;
  final Duration delay;
  Timer? _timer;

  String _username = '';
  UsernameStatus _status = UsernameStatus.empty;
  String? _problem;

  /// The username as it would be stored.
  String get username => _username;
  UsernameStatus get status => _status;

  /// Why it can't be used, for [UsernameStatus.invalid].
  String? get problem => _problem;

  bool get isAvailable => _status == UsernameStatus.available;

  /// What to show under the field; null when there's nothing to say.
  String? get message => switch (_status) {
    UsernameStatus.empty || UsernameStatus.checking => null,
    UsernameStatus.invalid => _problem,
    UsernameStatus.available => '@$_username is available',
    UsernameStatus.taken => '@$_username is taken',
    UsernameStatus.failed => "Couldn't check that username. Try again.",
  };

  void update(String input) {
    _timer?.cancel();
    _username = Username.normalize(input);
    _problem = _username.isEmpty ? null : Username.problem(_username);
    _status = _username.isEmpty
        ? UsernameStatus.empty
        : _problem != null
        ? UsernameStatus.invalid
        : UsernameStatus.checking;
    notifyListeners();
    if (_status == UsernameStatus.checking) {
      _timer = Timer(delay, () => _check(_username));
    }
  }

  /// It turned out to be taken (claimed by someone else meanwhile).
  void markTaken() {
    _timer?.cancel();
    _status = UsernameStatus.taken;
    notifyListeners();
  }

  Future<void> _check(String username) async {
    final result = await _auth.isUsernameAvailable(username);
    // Typed on since; that check will answer.
    if (username != _username) return;
    _status = switch (result) {
      Ok(value: true) => UsernameStatus.available,
      Ok(value: false) => UsernameStatus.taken,
      Error() => UsernameStatus.failed,
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
