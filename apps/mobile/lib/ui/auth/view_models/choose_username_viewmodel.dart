import 'package:flutter/foundation.dart';

import '../../../data/repositories/auth/auth_repository.dart';
import '../../../domain/models/username.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';
import 'username_checker.dart';

/// Picking a username, for people who signed up with Google or Apple (or
/// before usernames). The router lets them in once it's claimed.
class ChooseUsernameViewModel extends ChangeNotifier {
  ChooseUsernameViewModel({required AuthRepository authRepository})
    : _auth = authRepository,
      username = UsernameChecker(authRepository: authRepository) {
    claim = Command1<void, String>(_claim);
    signOut = Command0<void>(_auth.signOut);
  }

  final AuthRepository _auth;
  final UsernameChecker username;

  late final Command1<void, String> claim;
  late final Command0<void> signOut;

  /// The name to greet them with.
  String get name {
    final n = _auth.currentUser?.displayName?.trim() ?? '';
    return n.isEmpty ? '' : n.split(' ').first;
  }

  /// A starting suggestion from their name, e.g. "pat.lee"; checked like a
  /// typed one.
  String get suggestion {
    final n = (_auth.currentUser?.displayName ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    final s = n.length > Username.maxLength
        ? n.substring(0, Username.maxLength).replaceAll(RegExp(r'\.+$'), '')
        : n;
    return Username.problem(s) == null ? s : '';
  }

  Future<Result<void>> _claim(String input) async {
    final result = await _auth.claimUsername(input);
    if (result case Error(error: UsernameTakenException())) {
      username.markTaken();
    }
    return result;
  }

  @override
  void dispose() {
    username.dispose();
    claim.dispose();
    signOut.dispose();
    super.dispose();
  }
}
