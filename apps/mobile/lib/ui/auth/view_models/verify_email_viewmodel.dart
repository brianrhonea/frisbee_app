import 'package:flutter/foundation.dart';

import '../../../data/repositories/account_gate/account_gate.dart';
import '../../../data/repositories/auth/auth_repository.dart';
import '../../../data/repositories/personal/personal_repository.dart';
import '../../../utils/command.dart';
import '../../../utils/result.dart';

/// "Verify your email": the account can read but not write until Firebase
/// has verified its email (docs/specifications/contracts/account-gate.md).
/// Send (or resend) the email, then "I've verified" reloads the user and
/// takes a new ID token so the API and rules see it.
class VerifyEmailViewModel extends ChangeNotifier {
  VerifyEmailViewModel({
    required AuthRepository authRepository,
    required AccountGate accountGate,
    PersonalDetailsRepository? personalRepository,
  }) : _auth = authRepository,
       _gate = accountGate,
       _personal = personalRepository {
    send = Command0<void>(_auth.sendEmailVerification);
    check = Command0<bool>(_check);
    signOut = Command0<void>(_auth.signOut);
  }

  final AuthRepository _auth;
  final AccountGate _gate;
  final PersonalDetailsRepository? _personal;

  late final Command0<void> send;
  late final Command0<bool> check;
  late final Command0<void> signOut;

  /// The email address the message goes to.
  String? get email => _auth.currentUser?.email;

  bool _stillUnverified = false;

  /// "I've verified" ran and Firebase doesn't have it yet.
  bool get stillUnverified => _stillUnverified;

  Future<Result<bool>> _check() async {
    _stillUnverified = false;
    notifyListeners();
    final result = await _auth.checkEmailVerified();
    if (result case Ok(:final value)) {
      if (value) {
        _gate.clear(AccountGate.emailUnverified);
        // The token has new claims; ask the API again so a held-back claim
        // (age, terms) is set before the next write.
        await _personal?.refreshStatus();
      } else {
        _stillUnverified = true;
      }
    }
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    send.dispose();
    check.dispose();
    signOut.dispose();
    super.dispose();
  }
}
